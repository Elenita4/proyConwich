package com.example.test_code_02

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.test_code_02/drive_folder"
    private val folderRequestCode = 4107
    private var pendingFolderResult: MethodChannel.Result? = null

    private val printerChannelName = "com.example.test_code_02/bluetooth_printer"
    private val printerRequestCode = 4201
    private var pendingPrinterResult: MethodChannel.Result? = null
    private var pendingPrinterAction: String? = null
    private var pendingPrinterAddress: String? = null
    private var printerSocket: BluetoothSocket? = null
    private val sppUuid: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    // BLE GATT de la impresora Golden Sky GS-FJ80M-UB (transparent UART).
    private val bleServiceUuid: UUID =
        UUID.fromString("49535343-fe7d-4ae5-8fa9-9fafd205e455")
    private val bleWriteUuid: UUID =
        UUID.fromString("49535343-8841-43f4-a8d4-ecbe34729bb3")

    private var bluetoothGatt: BluetoothGatt? = null
    private var bleWriteChar: BluetoothGattCharacteristic? = null
    private var bleConnected = false
    private var bleAddress = ""
    private var bleConnectResult: MethodChannel.Result? = null
    private var bleFallbackDone = false
    private var blePrintResult: MethodChannel.Result? = null
    private var blePrintBytes: ByteArray? = null
    private var bleWriteOffset = 0
    private var bleLastChunk = 0
    private var bleChunkSize = 20
    private var bleConexionCompletada = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "pickFolder" -> pickFolder(result)
                        "checkPermission" -> {
                            val uri = call.argument<String>("uri")
                            result.success(
                                uri != null && hasWritePermission(Uri.parse(uri)),
                            )
                        }
                        "writeFile" -> {
                            val uri = call.argument<String>("uri")
                            val name = call.argument<String>("name")
                            val bytes = call.argument<ByteArray>("bytes")
                            if (uri == null || name == null || bytes == null) {
                                result.error("invalid_args", "Faltan datos.", null)
                            } else {
                                writeFile(Uri.parse(uri), name, bytes)
                                result.success(true)
                            }
                        }
                        "listFiles" -> {
                            val uri = call.argument<String>("uri")
                            if (uri == null) {
                                result.error("invalid_args", "Falta la carpeta.", null)
                            } else {
                                result.success(listFiles(Uri.parse(uri)))
                            }
                        }
                        "deleteFile" -> {
                            val uri = call.argument<String>("fileUri")
                            if (uri == null) {
                                result.error("invalid_args", "Falta el archivo.", null)
                            } else {
                                result.success(
                                    DocumentsContract.deleteDocument(
                                        contentResolver,
                                        Uri.parse(uri),
                                    ),
                                )
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("drive_error", error.message ?: "Error de Drive.", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, printerChannelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isAvailable" -> result.success(getBluetoothAdapter() != null)
                        "isOn" -> result.success(getBluetoothAdapter()?.isEnabled == true)
                        "openSettings" -> {
                            startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                            result.success(true)
                        }
                        "listBondedDevices" -> listBondedDevices(result)
                        "scanBleDevices" -> scanBleDevices(result)
                        "connect" -> {
                            val address = call.argument<String>("address")
                            connectPrinter(address, result)
                        }
                        "printBytes" -> {
                            val bytes = call.argument<ByteArray>("bytes")
                            sendBytes(bytes, result)
                        }
                        "disconnect" -> {
                            disconnectPrinter()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error(
                        "printer_error",
                        error.message ?: "Error de impresora.",
                        null,
                    )
                }
            }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("busy", "Ya hay un selector de carpeta abierto.", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, folderRequestCode)
        } catch (error: Exception) {
            pendingFolderResult = null
            result.error("drive_picker", error.message ?: "No se pudo abrir.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequestCode) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val takeFlags = (data?.flags ?: 0) and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (_: SecurityException) {
            // Si el proveedor no permite persistir, se intentará escribir igual.
        }
        result.success(
            hashMapOf(
                "uri" to uri.toString(),
                "name" to (displayName(uri) ?: "Carpeta de Drive"),
            ),
        )
    }

    private fun hasWritePermission(uri: Uri): Boolean =
        contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return null
    }

    private fun childDocumentsUri(folderUri: Uri): Uri {
        val treeId = DocumentsContract.getTreeDocumentId(folderUri)
        return DocumentsContract.buildChildDocumentsUriUsingTree(folderUri, treeId)
    }

    private fun documentUri(folderUri: Uri, documentId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(folderUri, documentId)

    private fun findChild(folderUri: Uri, name: String): Uri? {
        contentResolver.query(
            childDocumentsUri(folderUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val display = cursor.getString(1)
                if (display == name) {
                    return documentUri(folderUri, cursor.getString(0))
                }
            }
        }
        return null
    }

    private fun writeFile(folderUri: Uri, name: String, bytes: ByteArray) {
        findChild(folderUri, name)?.let {
            DocumentsContract.deleteDocument(contentResolver, it)
        }
        val parent = documentUri(
            folderUri,
            DocumentsContract.getTreeDocumentId(folderUri),
        )
        val nuevo = DocumentsContract.createDocument(
            contentResolver,
            parent,
            "application/octet-stream",
            name,
        ) ?: throw IllegalStateException("No se pudo crear el archivo.")
        contentResolver.openOutputStream(nuevo, "w")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IllegalStateException("No se pudo abrir el archivo.")
    }

    private fun listFiles(folderUri: Uri): List<Map<String, Any?>> {
        val archivos = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childDocumentsUri(folderUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                archivos.add(
                    hashMapOf(
                        "uri" to documentUri(folderUri, documentId).toString(),
                        "name" to cursor.getString(1),
                        "size" to if (cursor.isNull(2)) 0 else cursor.getLong(2),
                        "modified" to if (cursor.isNull(3)) null else cursor.getLong(3),
                    ),
                )
            }
        }
        return archivos
    }

    // --- Impresora térmica Bluetooth (ESC/POS por SPP) ---

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return manager?.adapter
    }

    private fun ensureBluetoothConnectPermission(
        result: MethodChannel.Result,
        action: String,
        address: String? = null,
    ): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.BLUETOOTH_CONNECT,
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                pendingPrinterResult = result
                pendingPrinterAction = action
                pendingPrinterAddress = address
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
                    printerRequestCode,
                )
                return false
            }
        }
        return true
    }

    private fun listBondedDevices(result: MethodChannel.Result) {
        if (!ensureBluetoothConnectPermission(result, "list")) return
        try {
            val adapter = getBluetoothAdapter()
            if (adapter == null) {
                result.error("no_bluetooth", "Este dispositivo no tiene Bluetooth.", null)
                return
            }
            val lista = adapter.bondedDevices.map {
                hashMapOf(
                    "name" to (it.name ?: ""),
                    "address" to it.address,
                    "type" to it.type,
                )
            }
            result.success(lista)
        } catch (error: SecurityException) {
            result.error(
                "no_permissions",
                error.message ?: "Sin permiso de Bluetooth.",
                null,
            )
        }
    }

    private fun createSocketByChannel(
        device: BluetoothDevice,
        canal: Int,
        inseguro: Boolean,
    ): BluetoothSocket {
        val metodo = BluetoothDevice::class.java.getMethod(
            if (inseguro) "createInsecureRfcommSocket" else "createRfcommSocket",
            Int::class.java,
        )
        return metodo.invoke(device, canal) as BluetoothSocket
    }

    private fun connectPrinter(address: String?, result: MethodChannel.Result) {
        if (address.isNullOrEmpty()) {
            result.error("invalid_args", "Falta la dirección de la impresora.", null)
            return
        }
        if (!ensureBluetoothConnectPermission(result, "connect", address)) return
        val adapter = getBluetoothAdapter()
        if (adapter == null) {
            result.error("no_bluetooth", "Este dispositivo no tiene Bluetooth.", null)
            return
        }
        if (bleConnected && bleAddress == address) {
            result.success(true)
            return
        }
        try {
            adapter.cancelDiscovery()
        } catch (_: Exception) {
            // Ignorar.
        }
        // 1) Intentar BLE GATT (la GS-FJ80M-UB usa BLE).
        val device = try {
            adapter.getRemoteDevice(address)
        } catch (error: Exception) {
            result.error("invalid_args", error.message ?: "Dirección inválida.", null)
            return
        }
        disconnectBle()
        bleAddress = address
        bleConnectResult = result
        bleFallbackDone = false
        bleConexionCompletada = false
        bleChunkSize = 20
        val started = try {
            bluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(this, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(this, false, gattCallback)
            }
            bluetoothGatt != null
        } catch (_: Exception) {
            false
        }
        if (!started) {
            bleConnectResult = null
            connectSpp(address, result)
            return
        }
        // 2) Si el BLE no conecta en 6 s, caer a SPP.
        Handler(Looper.getMainLooper()).postDelayed({
            if (!bleConnected && bleConnectResult === result) {
                fallbackToSpp()
            }
        }, 6000)
    }

    private fun connectSpp(address: String, result: MethodChannel.Result) {
        val adapter = getBluetoothAdapter()
        if (adapter == null) {
            result.error("no_bluetooth", "Este dispositivo no tiene Bluetooth.", null)
            return
        }
        Thread {
            var ultimoError = "No se pudo conectar."
            var exito = false
            try {
                val device = adapter.getRemoteDevice(address)
                // Algunas térmicas solo aceptan el socket inseguro o el canal 1.
                val intentos: List<() -> BluetoothSocket> = listOf(
                    { device.createInsecureRfcommSocketToServiceRecord(sppUuid) },
                    { device.createRfcommSocketToServiceRecord(sppUuid) },
                    { createSocketByChannel(device, 1, true) },
                    { createSocketByChannel(device, 1, false) },
                    { device.createInsecureRfcommSocketToServiceRecord(sppUuid) },
                )
                for ((indice, crear) in intentos.withIndex()) {
                    if (exito) break
                    var socket: BluetoothSocket? = null
                    try {
                        disconnectSpp()
                        socket = crear()
                        socket.connect()
                        printerSocket = socket
                        exito = true
                    } catch (error: Exception) {
                        val mensaje = error.message ?: error.javaClass.simpleName
                        ultimoError = "Intento ${indice + 1}: $mensaje"
                        try {
                            socket?.close()
                        } catch (_: Exception) {
                            // Ignorar.
                        }
                        try {
                            Thread.sleep(250)
                        } catch (_: InterruptedException) {
                            // Ignorar.
                        }
                    }
                }
            } catch (error: Exception) {
                ultimoError = error.message ?: "No se pudo conectar."
            }
            runOnUiThread {
                if (exito) {
                    result.success(true)
                } else {
                    result.error("connect_error", ultimoError, null)
                }
            }
        }.start()
    }

    private fun fallbackToSpp() {
        if (bleFallbackDone) return
        bleFallbackDone = true
        val result = bleConnectResult ?: return
        val address = bleAddress
        bleConnectResult = null
        disconnectBle()
        if (address.isEmpty()) {
            result.error("connect_error", "No se pudo conectar.", null)
            return
        }
        connectSpp(address, result)
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(
            gatt: BluetoothGatt,
            status: Int,
            newState: Int,
        ) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                try {
                    gatt.discoverServices()
                } catch (_: Exception) {
                    fallbackToSpp()
                }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                Log.w("PrinterBLE", "desconectado status=$status")
                bleConnected = false
                bleConexionCompletada = false
                bleWriteChar = null
                if (bleConnectResult != null) {
                    fallbackToSpp()
                }
                if (blePrintResult != null) {
                    completeBlePrint(
                        false,
                        "Desconectado durante la impresión (status=$status).",
                    )
                }
                try {
                    gatt.close()
                } catch (_: Exception) {
                    // Ignorar.
                }
                if (bluetoothGatt === gatt) bluetoothGatt = null
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            if (status != BluetoothGatt.GATT_SUCCESS) {
                fallbackToSpp()
                return
            }
            val service = gatt.getService(bleServiceUuid)
            val writeChar = service?.getCharacteristic(bleWriteUuid)
            if (service == null || writeChar == null) {
                fallbackToSpp()
                return
            }
            bleWriteChar = writeChar
            // No se habilitan notificaciones: el writeDescriptor dejaría el
            // stack GATT ocupado y la primera escritura fallaría con BUSY.
            // No se cambia la prioridad de conexión: en esta térmica provocaba
            // desconexiones (status=22) durante la impresión.
            val pidioMtu = try {
                gatt.requestMtu(247)
            } catch (_: Exception) {
                false
            }
            if (!pidioMtu) {
                finishBleConnection()
            } else {
                // Si la impresora no responde al MTU, no bloquear la conexión.
                Handler(Looper.getMainLooper()).postDelayed({
                    finishBleConnection()
                }, 500)
            }
        }

        override fun onMtuChanged(
            gatt: BluetoothGatt,
            mtu: Int,
            status: Int,
        ) {
            bleChunkSize = if (status == BluetoothGatt.GATT_SUCCESS) {
                (mtu - 3).coerceIn(20, 96)
            } else {
                20
            }
            Log.d("PrinterBLE", "MTU=$mtu status=$status chunk=$bleChunkSize")
            finishBleConnection()
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            if (characteristic.uuid != bleWriteUuid) return
            if (status == BluetoothGatt.GATT_SUCCESS) {
                bleWriteOffset += bleLastChunk
                val total = blePrintBytes?.size ?: 0
                Log.d(
                    "PrinterBLE",
                    "write ok offset=$bleWriteOffset/$total chunk=$bleLastChunk",
                )
                if (bleWriteOffset < total) {
                    // Pausa breve para que el UART de la térmica drene el buffer.
                    Handler(Looper.getMainLooper()).postDelayed({
                        writeNextChunk()
                    }, 8)
                } else {
                    completeBlePrint(true)
                }
                return
            }
            Log.w(
                "PrinterBLE",
                "write fail status=$status offset=$bleWriteOffset/" +
                    "${blePrintBytes?.size ?: 0}",
            )
            // Si el modo con respuesta falla, reintentar ese chunk sin respuesta.
            val data = blePrintBytes
            if (data != null && bleWriteOffset < data.size) {
                val fin = minOf(bleWriteOffset + bleChunkSize, data.size)
                val chunk = data.copyOfRange(bleWriteOffset, fin)
                bleLastChunk = chunk.size
                val st = try {
                    writeChunkStatus(gatt, characteristic, chunk, withResponse = false)
                } catch (_: Exception) {
                    Int.MIN_VALUE
                }
                if (st == 0) {
                    avanzarSinRespuesta()
                    return
                }
                if (bleChunkSize > 20) {
                    bleChunkSize = 20
                    writeNextChunk()
                    return
                }
                completeBlePrint(
                    false,
                    "onCharacteristicWrite status=$status; NO_RESPONSE status=$st; " +
                        "offset=$bleWriteOffset/${data.size}",
                )
                return
            }
            completeBlePrint(
                false,
                "onCharacteristicWrite status=$status; offset=$bleWriteOffset",
            )
        }
    }

    private fun finishBleConnection() {
        if (bleConexionCompletada || bleWriteChar == null) return
        bleConexionCompletada = true
        bleConnected = true
        val result = bleConnectResult
        bleConnectResult = null
        result?.success(true)
    }

    private fun writeNextChunk() {
        val gatt = bluetoothGatt
        val char = bleWriteChar
        val data = blePrintBytes
        if (gatt == null || char == null || data == null) {
            completeBlePrint(
                false,
                "GATT no disponible (gatt=${gatt != null}, " +
                    "char=${char != null}, data=${data != null}).",
            )
            return
        }
        if (bleWriteOffset >= data.size) {
            completeBlePrint(true)
            return
        }
        val fin = minOf(bleWriteOffset + bleChunkSize, data.size)
        val chunk = data.copyOfRange(bleWriteOffset, fin)
        bleLastChunk = chunk.size
        Log.d(
            "PrinterBLE",
            "write offset=$bleWriteOffset/${data.size} chunk=${chunk.size}",
        )
        // 1) Con respuesta (permite detectar errores).
        val stDefault = try {
            writeChunkStatus(gatt, char, chunk, withResponse = true)
        } catch (_: Exception) {
            Int.MIN_VALUE
        }
        if (stDefault == 0) return // espera onCharacteristicWrite
        // 2) Sin respuesta (algunas térmicas solo aceptan este modo).
        val stNoResp = try {
            writeChunkStatus(gatt, char, chunk, withResponse = false)
        } catch (_: Exception) {
            Int.MIN_VALUE
        }
        if (stNoResp == 0) {
            avanzarSinRespuesta()
        } else if (bleChunkSize > 20) {
            // Algunas térmicas no aceptan chunks grandes aunque el MTU lo
            // permita; se vuelve a 20 bytes sin perder el avance.
            bleChunkSize = 20
            writeNextChunk()
        } else {
            completeBlePrint(
                false,
                "Escritura rechazada: DEFAULT status=$stDefault, " +
                    "NO_RESPONSE status=$stNoResp, offset=$bleWriteOffset/${data.size}",
            )
        }
    }

    /// Devuelve el código de estado de `writeCharacteristic` (0 = aceptado).
    private fun writeChunkStatus(
        gatt: BluetoothGatt,
        char: BluetoothGattCharacteristic,
        chunk: ByteArray,
        withResponse: Boolean,
    ): Int {
        val tipo = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeCharacteristic(char, chunk, tipo)
        } else {
            char.writeType = tipo
            char.value = chunk
            if (gatt.writeCharacteristic(char)) 0 else -1
        }
    }

    /// Escritura sin respuesta: no hay callback, se avanza con un pequeño delay.
    private fun avanzarSinRespuesta() {
        bleWriteOffset += bleLastChunk
        val total = blePrintBytes?.size ?: 0
        if (bleWriteOffset < total) {
            Handler(Looper.getMainLooper()).postDelayed({ writeNextChunk() }, 25)
        } else {
            Handler(Looper.getMainLooper()).postDelayed({ completeBlePrint(true) }, 120)
        }
    }

    private fun completeBlePrint(ok: Boolean, detalle: String? = null) {
        val result = blePrintResult ?: return
        blePrintResult = null
        blePrintBytes = null
        bleWriteOffset = 0
        bleLastChunk = 0
        if (ok) {
            result.success(true)
        } else {
            result.error(
                "ble_write",
                detalle ?: "No se pudieron enviar los datos por BLE.",
                null,
            )
        }
    }

    private fun sendBytes(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null) {
            result.error("invalid_args", "Faltan los datos a imprimir.", null)
            return
        }
        // 1) BLE GATT.
        if (bleConnected && bluetoothGatt != null && bleWriteChar != null) {
            if (blePrintResult != null) {
                result.error("busy", "Ya hay una impresión en curso.", null)
                return
            }
            blePrintResult = result
            blePrintBytes = bytes
            bleWriteOffset = 0
            bleLastChunk = 0
            writeNextChunk()
            return
        }
        // 2) SPP de respaldo.
        val socket = printerSocket
        if (socket == null) {
            result.error("not_connected", "No hay impresora conectada.", null)
            return
        }
        Thread {
            var ultimoError = "No se pudo imprimir."
            var exito = false
            for (intento in 0..1) {
                if (exito) break
                try {
                    val output = socket.outputStream
                    output.write(bytes)
                    output.flush()
                    exito = true
                } catch (error: Exception) {
                    ultimoError = error.message ?: error.javaClass.simpleName
                    try {
                        Thread.sleep(300)
                    } catch (_: InterruptedException) {
                        // Ignorar.
                    }
                }
            }
            runOnUiThread {
                if (exito) {
                    result.success(true)
                } else {
                    result.error("write_error", ultimoError, null)
                }
            }
        }.start()
    }

    private fun disconnectSpp() {
        try {
            printerSocket?.close()
        } catch (_: Exception) {
            // Ignorar si ya estaba cerrado.
        }
        printerSocket = null
    }

    private fun disconnectBle() {
        bleConnected = false
        bleConexionCompletada = false
        bleChunkSize = 20
        bleWriteChar = null
        if (blePrintResult != null) {
            completeBlePrint(false, "Desconectado antes de terminar la impresión.")
        }
        try {
            bluetoothGatt?.disconnect()
        } catch (_: Exception) {
            // Ignorar.
        }
        try {
            bluetoothGatt?.close()
        } catch (_: Exception) {
            // Ignorar.
        }
        bluetoothGatt = null
    }

    private fun disconnectPrinter() {
        disconnectBle()
        disconnectSpp()
    }

    private fun ensureScanPermissions(result: MethodChannel.Result): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val scanOk = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_SCAN,
            ) == PackageManager.PERMISSION_GRANTED
            val connectOk = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED
            if (!scanOk || !connectOk) {
                pendingPrinterResult = result
                pendingPrinterAction = "scan"
                pendingPrinterAddress = null
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.BLUETOOTH_SCAN,
                        Manifest.permission.BLUETOOTH_CONNECT,
                    ),
                    printerRequestCode,
                )
                return false
            }
        }
        return true
    }

    private fun scanBleDevices(result: MethodChannel.Result) {
        if (!ensureScanPermissions(result)) return
        val adapter = getBluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            result.error("bluetooth_off", "Activa el Bluetooth.", null)
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            result.error("no_ble", "Este dispositivo no tiene escáner BLE.", null)
            return
        }
        val encontrados = linkedMapOf<String, HashMap<String, Any?>>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, res: ScanResult) {
                val device = res.device
                encontrados[device.address] = hashMapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address,
                    "rssi" to res.rssi,
                    "type" to device.type,
                )
            }
        }
        try {
            scanner.startScan(callback)
        } catch (error: SecurityException) {
            result.error("no_permissions", error.message ?: "Sin permiso.", null)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                scanner.stopScan(callback)
            } catch (_: Exception) {
                // Ignorar.
            }
            result.success(encontrados.values.toList())
        }, 7000)
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != printerRequestCode) return
        val result = pendingPrinterResult ?: return
        val action = pendingPrinterAction
        val address = pendingPrinterAddress
        pendingPrinterResult = null
        pendingPrinterAction = null
        pendingPrinterAddress = null
        val concedido = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!concedido) {
            result.error("no_permissions", "Se requiere permiso de Bluetooth.", null)
            return
        }
        when (action) {
            "connect" -> connectPrinter(address, result)
            "scan" -> scanBleDevices(result)
            else -> listBondedDevices(result)
        }
    }
}
