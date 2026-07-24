# 技術術語對照表

決策討論用到的專有名詞,一條一句白話 + 在本專案的意義。領域(業務)名詞見根目錄 `CONTEXT.md`。

| 術語 | 白話解釋 | 在本專案的意義 |
|------|---------|--------------|
| **offline-first(離線優先)** | App 先讀寫手機本地資料庫、畫面立即反應,連網時才背景同步 | 所有畫面直接讀寫本機 Drift,不等網路 |
| **sync engine(同步引擎)** | 自動在本機 DB 與雲端 DB 間搬資料、解衝突的元件 | 候選:PowerSync;選它就不用自己寫同步 |
| **LWW(last-write-wins,後寫覆蓋)** | 同一筆資料在多裝置被改時,以最後寫入者為準 | 單人多裝置的衝突策略,夠用 |
| **CRDT** | 數學上保證多端同時修改能自動合併不衝突的資料結構 | 多人協作才需要;我們單人用 LWW 就好,列出是為了說明為何不用更重的方案 |
| **Drift** | Flutter 的 SQLite ORM(資料庫存取層),支援型別安全查詢與 code-gen | 現有資料層核心:11 張表、7 個 repository 都建在它上面 |
| **WASM(WebAssembly)** | 讓 C 寫的程式(如 SQLite)編譯成瀏覽器能跑的位元碼 | Flutter web 上跑 SQLite 靠它 |
| **OPFS(Origin-Private File System)** | 瀏覽器給網站的私有高速檔案系統 | web 版 SQLite 的儲存底層,主流瀏覽器已支援 |
| **Supabase** | 開源的 Firebase 替代品:托管 Postgres + 帳號驗證 + API | 候選後端:雲端資料庫與登入服務 |
| **PowerSync** | 專做「本機 SQLite ↔ 雲端 Postgres」的同步引擎服務 | 候選同步方案,可保留現有 Drift 資料層 |
| **PowerSync Schema** | 給 PowerSync 的一份表結構宣告(型別只有 text/integer/real、欄位皆可空) | 採用的話要額外維護,與 Drift 11 張表對照 |
| **offline persistence(離線持久化)** | Firestore 把雲端資料快取在本機、斷網仍可讀寫的功能 | 只在 Firebase 方案出現;那是快取,不是真正的本機資料庫 |
| **Firestore** | Firebase 的文件式(非關聯式)雲端資料庫 | 落選方向:採用等於重寫整個關聯式資料層 |
| **Services ID + .p8 key** | Apple 給「非原生平台」做 Apple 登入的憑證設定(走網頁跳轉) | web/Android 要做 Apple 登入就得辦;iOS 原生不用 |
| **redirect flow(跳轉登入流)** | 登入時跳到供應商網頁認證再跳回 app 的流程 | web/Android 的 Apple 登入走這條 |
| **idToken** | 登入供應商簽發的身分證明權杖,後端驗它確認你是誰 | iOS 原生 Apple 登入拿到後直接交給後端換 session |
| **embedded replica(內嵌副本)** | 把一份雲端資料庫的本機副本放在裝置上,呼叫同步對拉 | Turso 方案的核心概念,列為觀望 |
| **墓碑(tombstone)** | 刪除資料時不真的刪,留一筆「已刪除」標記,讓其他裝置同步時知道要跟著刪 | 自寫同步的刪除傳播機制;沒有它,離線裝置永遠不知道某筆被刪了 |
| **增量同步(delta sync)** | 只傳「上次同步之後有變動的資料」,不每次全量搬 | 用 updatedAt 時間戳當游標,拉推兩向都走增量 |
| **Litestream** | 把 SQLite 的變動即時串流備份到雲端儲存的工具 | 自建後端的備份方案:server 上的 SQLite 自動備份,免手動 |
| **S3 相容儲存** | 遵循 Amazon S3 API 的物件儲存服務(很多家都有,含自架 MinIO) | Litestream 備份的目的地,不綁定特定廠商 |
| **meta 1.17.0 天花板** | Flutter 3.38.5 SDK 釘死的內部套件版本,擋住新版 analyzer/drift 等整條鏈 | 先前一切降版妥協的根因;升 Flutter(Dart≥3.11)後解除 |
| **MethodChannel** | Flutter 與原生(Swift/Kotlin)程式碼互相呼叫的橋 | 用它從 iOS 原生讀舊版 UserDefaults 偏好 |
| **CoreData** | Apple 的資料持久化框架,舊 Swift 版的資料庫(底層也是 SQLite) | 無縫匯入的資料來源 |
