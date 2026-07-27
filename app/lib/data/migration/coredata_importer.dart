// 舊 CoreData(WorkoutRecord.sqlite)→ Drift 無縫匯入的平台分流入口。
//
// native(io)平台(Android/iOS/桌面)走 coredata_importer_io.dart 的真實
// 匯入實作;web 平台走 coredata_importer_web.dart 的 no-op stub(web 天然
// 不可能有舊 iOS App 的 CoreData 檔,且 dart:io / package:sqlite3 的 FFI
// 綁定在 dart2js 編譯不過,見 app/lib/data/db/README.md web 支援章節)。
//
// 呼叫端(main.dart / 測試)一律 import 這個檔案,拿到的都是同一個
// `CoreDataImporter` / `ImportResult` 介面,不需要知道目前平台。
export 'coredata_importer_io.dart'
    if (dart.library.js_interop) 'coredata_importer_web.dart';
