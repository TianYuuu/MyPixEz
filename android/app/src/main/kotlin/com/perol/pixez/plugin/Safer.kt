package com.perol.pixez.plugin

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileInputStream
import java.io.FileOutputStream

object Safer {
    private const val SAF_CHANNEL = "com.perol.dev/saf"
    private const val CREATE_FILE_CODE = 1111
    private const val OPEN_FILE_CODE = 2222
    private const val PICK_DIRECTORY_CODE = 3333
    private var pendingResult: MethodChannel.Result? = null

    fun bindChannel(activity: Activity, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SAF_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "createFile" -> {
                    pendingResult = result
                    val name = call.argument<String>("name")!!
                    val mimeType = call.argument<String>("mimeType")!!
                    activity.createFile(name, mimeType)
                }

                "writeUri" -> {
                    pendingResult = result
                    val uriString = call.argument<String>("uri")!!
                    val byteArray = call.argument<ByteArray>("data")!!
                    val uri = Uri.parse(uriString)
                    activity.writeUri(uri, byteArray)
                }

                "openFile" -> {
                    pendingResult = result
                    val type = call.argument<String>("type")
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        this.type = type
                    }
                    activity.startActivityForResult(intent, OPEN_FILE_CODE)
                }

                "pickDirectory" -> {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                        )
                    }
                    activity.startActivityForResult(intent, PICK_DIRECTORY_CODE)
                }

                "writeToDirectory" -> {
                    pendingResult = result
                    val uriString = call.argument<String>("uri")!!
                    val name = call.argument<String>("name")!!
                    val mimeType = call.argument<String>("mimeType") ?: "text/plain"
                    val byteArray = call.argument<ByteArray>("data")!!
                    activity.writeToDirectory(Uri.parse(uriString), name, mimeType, byteArray)
                }
            }
        }
    }

    fun Activity.createFile(name: String, mimeType: String) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeType
            putExtra(Intent.EXTRA_TITLE, name)
        }
        startActivityForResult(intent, CREATE_FILE_CODE)
    }

    fun bindResult(
        activity: Activity,
        requestCode: Int, resultCode: Int,
        data: Intent?
    ) {
        if (resultCode == Activity.RESULT_OK) {
            when (requestCode) {
                CREATE_FILE_CODE -> {
                    val uriString = data?.data?.toString()
                    if (!uriString.isNullOrBlank()) {
                        pendingResult?.success(uriString)
                        pendingResult = null
                        return
                    }
                }

                OPEN_FILE_CODE -> {
                    try {
                        val uri = data!!.data!!
                        val contentResolver = activity.contentResolver
                        contentResolver.openFileDescriptor(uri, "r")!!.use {
                            FileInputStream(it.fileDescriptor).use {
                                val byteArray = it.readBytes()
                                pendingResult?.success(byteArray)
                                pendingResult = null
                                return
                            }
                        }
                    } catch (e: Throwable) {
                        Log.d("Safer", "bindResult: ${e.message}")
                    }
                }

                PICK_DIRECTORY_CODE -> {
                    val uri = data?.data
                    if (uri != null) {
                        try {
                            activity.contentResolver.takePersistableUriPermission(
                                uri,
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                            )
                        } catch (e: Throwable) {
                            Log.d("Safer", "takePersistableUriPermission: ${e.message}")
                        }
                        val name = queryTreeDisplayName(activity, uri)
                            ?: DocumentsContract.getTreeDocumentId(uri)
                        pendingResult?.success(mapOf("uri" to uri.toString(), "name" to name))
                        pendingResult = null
                        return
                    }
                }
            }
        }
        pendingResult?.error("d", "d", "d")
        pendingResult = null
    }

    private fun queryTreeDisplayName(activity: Activity, uri: Uri): String? {
        return try {
            activity.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null,
                null,
                null
            )?.use {
                if (it.moveToFirst()) it.getString(0) else null
            }
        } catch (e: Throwable) {
            Log.d("Safer", "queryTreeDisplayName: ${e.message}")
            null
        }
    }

    private fun findChild(
        resolver: ContentResolver,
        treeUri: Uri,
        parentDocumentId: String,
        name: String
    ): Uri? {
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentDocumentId)
        resolver.query(
            childrenUri,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME
            ),
            null,
            null,
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(1) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(
                        treeUri,
                        cursor.getString(0)
                    )
                }
            }
        }
        return null
    }

    /**
     * 把文件直接写进用户选过的文件夹（SAF tree），同名文件覆盖。
     * 失败时用 PlatformException 把原因带回 Dart，由 Dart 决定回退到手选位置。
     */
    fun Activity.writeToDirectory(
        treeUri: Uri,
        name: String,
        mimeType: String,
        byteArray: ByteArray
    ) {
        try {
            val resolver = contentResolver
            val parentDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
            val parentUri =
                DocumentsContract.buildDocumentUriUsingTree(treeUri, parentDocumentId)
            val existing = findChild(resolver, treeUri, parentDocumentId, name)
            val uri = existing
                ?: DocumentsContract.createDocument(resolver, parentUri, mimeType, name)
                ?: throw IllegalStateException("cannot create $name")
            resolver.openOutputStream(uri, "wt")?.use {
                it.write(byteArray)
            } ?: throw IllegalStateException("cannot open $name")
            pendingResult?.success(uri.toString())
            pendingResult = null
        } catch (e: Throwable) {
            Log.d("Safer", "writeToDirectory: ${e.message}")
            pendingResult?.error("write_failed", e.message ?: "write failed", null)
            pendingResult = null
        }
    }

    fun Activity.writeUri(uri: Uri, byteArray: ByteArray) {
        try {
            contentResolver.openFileDescriptor(uri, "wt")?.use {
                FileOutputStream(it.fileDescriptor).use {
                    it.write(byteArray)
                }
            }
            pendingResult?.success("${uri}")
            pendingResult = null
        } catch (e: Throwable) {
            pendingResult?.error("d", "d", "d")
            pendingResult = null
        }
    }
}