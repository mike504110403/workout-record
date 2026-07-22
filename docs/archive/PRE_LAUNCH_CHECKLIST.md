# 🚀 產品上線準備檢查清單

## 📌 概述
此文檔確保 WorkoutRecord iOS App 能夠安全、穩定地上架 App Store，並具備未來擴展能力。

---

## ✅ 核心功能檢查（已完成）

### 基礎功能
- [x] 訓練記錄（動作、組數、重量、次數）
- [x] 體重追蹤
- [x] 個人記錄（PR）自動追蹤
- [x] 三項力量記錄（深蹲、臥推、硬舉）
- [x] 訓練模板
- [x] 數據分析圖表（訓練容量、肌群分布）
- [x] 歷史記錄查看
- [x] 休息計時器

### 用戶體驗
- [x] 新手引導流程
- [x] Apple ID 登入
- [x] 隱私政策同意
- [x] 全域設定（重量單位、主題、休息時間）
- [x] 滑動刪除動作
- [x] 淺色/深色模式

### 數據管理
- [x] CoreData 本地存儲
- [x] 自動遷移基礎設施
- [x] 數據完整性檢查

---

## ⚠️ 必須補充的功能（上線前）

### 1. 版本管理與強制更新系統 ❌

**目的：**
- 確保用戶使用最新版本
- 修復關鍵 Bug 時強制更新
- 提供版本更新提示

**需要實現：**
1. App 版本檢查機制
2. 最低支援版本配置（Firebase Remote Config）
3. 強制更新彈窗
4. 可選更新提示
5. 更新日誌顯示

**技術方案：**
```swift
// 1. 創建 VersionManager.swift
// 2. 從 Firebase Remote Config 獲取最低版本
// 3. 比對當前版本
// 4. 顯示更新彈窗
```

---

### 2. Firebase Authentication 用戶記錄 ❌

**目的：**
- 記錄用戶基本信息
- 為未來訂閱功能準備
- 跨設備識別用戶

**需要存儲的數據：**
```json
{
  "uid": "firebase-user-id",
  "appleID": "anonymized-apple-id",
  "email": "privaterelay@email.com",
  "displayName": "用戶名稱",
  "createdAt": "2025-10-29T12:00:00Z",
  "lastLoginAt": "2025-10-29T12:00:00Z",
  "deviceInfo": {
    "platform": "iOS",
    "osVersion": "17.0",
    "appVersion": "1.0.0"
  },
  "subscription": {
    "status": "free",
    "tier": "basic"
  }
}
```

**技術方案：**
```swift
// 1. 創建 FirebaseAuthService.swift
// 2. Apple ID 登入後同步到 Firebase Auth
// 3. 在 Firestore 創建 users/{uid} 文檔
// 4. 記錄基本資訊（不含訓練數據）
```

---

### 3. 增強 CoreData 遷移策略 ⚠️

**目前狀態：**
- ✅ 自動遷移已啟用
- ❌ 沒有版本控制
- ❌ 遷移失敗時只能刪除數據

**需要改進：**
1. 版本號管理（Model Version）
2. 輕量級遷移（Lightweight Migration）
3. 自訂遷移策略（Custom Migration）
4. 遷移前數據備份
5. 遷移失敗恢復機制

**技術方案：**
```swift
// 1. 在 .xcdatamodeld 中創建版本
// 2. 添加 Mapping Model
// 3. 遷移前備份到 iCloud/Firebase
// 4. 提供數據恢復選項
```

---

### 4. 用戶行為分析強化 ⚠️

**目前狀態：**
- ✅ Firebase Analytics 已集成
- ❌ 事件追蹤不完整

**需要追蹤的關鍵事件：**

#### 用戶生命週期
- `app_first_open` - 首次開啟
- `user_signup_completed` - 完成註冊
- `onboarding_completed` - 完成新手引導
- `user_login` - 用戶登入

#### 核心功能使用
- `workout_started` - 開始訓練
- `workout_completed` - 完成訓練
- `exercise_added` - 添加動作
- `set_completed` - 完成組數
- `pr_achieved` - 達成 PR
- `template_created` - 創建模板
- `template_used` - 使用模板

#### 數據分析
- `stats_viewed` - 查看數據頁面
- `chart_type_selected` - 選擇圖表類型
- `date_range_changed` - 切換時間範圍

#### 設定與偏好
- `weight_unit_changed` - 切換重量單位
- `theme_changed` - 切換主題
- `rest_time_adjusted` - 調整休息時間

#### 付費相關（未來）
- `subscription_page_viewed` - 查看訂閱頁面
- `subscription_started` - 開始訂閱
- `subscription_cancelled` - 取消訂閱

**技術方案：**
```swift
// 擴展 AnalyticsService.swift
// 在關鍵操作點添加事件記錄
```

---

### 5. 生產環境配置 ❌

**需要配置：**

#### Firebase
- ✅ Analytics - 已啟用
- ❌ Remote Config - 需設置
- ❌ Authentication - 需啟用
- ❌ Firestore - 需創建
- ❌ Crashlytics - 需設置

#### API 配置
- ❌ Production API URL（目前是 localhost）
- ❌ API Key 管理
- ❌ 環境變數配置

#### App Store 配置
- ❌ App ID 設置
- ❌ Bundle Identifier 確認
- ❌ App Icon（所有尺寸）
- ❌ Launch Screen
- ❌ 隱私權清單（Privacy Manifest）
- ❌ App Store Screenshots
- ❌ App Store Description

---

## 🔐 安全性檢查

### 數據安全
- [ ] API Key 不在代碼中（使用環境變數）
- [ ] 敏感數據加密存儲
- [ ] HTTPS 強制使用
- [ ] Certificate Pinning（可選）

### 隱私合規
- [x] 隱私政策頁面
- [ ] 數據收集說明完整
- [ ] Firebase 數據收集說明
- [ ] 第三方 SDK 列表
- [ ] 用戶數據刪除功能

---

## 📱 App Store 審核準備

### 必要資訊
- [ ] App Name
- [ ] App Subtitle
- [ ] Keywords
- [ ] Description（繁中、英文）
- [ ] Support URL
- [ ] Privacy Policy URL
- [ ] Marketing URL（可選）

### 截圖要求
- [ ] 6.7" Display（iPhone 15 Pro Max）
- [ ] 6.5" Display（iPhone 14 Plus）
- [ ] 5.5" Display（iPhone 8 Plus）
- [ ] 每個尺寸 3-10 張截圖
- [ ] 淺色/深色模式各一組

### App Review 資訊
- [ ] 測試帳號（Apple ID）
- [ ] 功能說明
- [ ] 審核備註
- [ ] 聯絡資訊

---

## 🧪 測試檢查清單

### 功能測試
- [ ] 所有核心流程測試
- [ ] 新手引導流程測試
- [ ] 數據CRUD測試
- [ ] 離線功能測試
- [ ] 數據同步測試（未來）

### 設備測試
- [ ] iPhone SE（小螢幕）
- [ ] iPhone 15 Pro（標準螢幕）
- [ ] iPhone 15 Pro Max（大螢幕）
- [ ] iPad（可選）

### iOS 版本測試
- [ ] iOS 16.0（最低支援）
- [ ] iOS 17.0
- [ ] iOS 18.0（最新）

### 邊界測試
- [ ] 網路中斷
- [ ] 數據量極大情況
- [ ] 快速連續操作
- [ ] 記憶體壓力測試
- [ ] 電池消耗測試

---

## 🚀 上線流程

### 階段 1: 開發完成（目前）
- [x] 核心功能開發
- [x] UI/UX 設計
- [x] 基礎測試

### 階段 2: 補充必要功能（2-3 天）
- [ ] 實現版本管理
- [ ] Firebase Auth 整合
- [ ] 強化分析事件
- [ ] 生產環境配置

### 階段 3: 內部測試（1 週）
- [ ] TestFlight Internal Testing
- [ ] Bug 修復
- [ ] 性能優化

### 階段 4: 外部測試（1-2 週）
- [ ] TestFlight External Testing
- [ ] 收集用戶反饋
- [ ] 最終調整

### 階段 5: App Store 提交
- [ ] 準備 App Store 資料
- [ ] 提交審核
- [ ] 回應審核問題
- [ ] 上架發布

---

## 📊 上線後監控

### 關鍵指標
- DAU/MAU（日活/月活用戶）
- 留存率（Day 1, Day 7, Day 30）
- 崩潰率（Crash Rate < 1%）
- ANR 率（App Not Responding < 0.1%）
- 平均使用時長
- 核心功能使用率

### 監控工具
- Firebase Analytics（用戶行為）
- Firebase Crashlytics（崩潰報告）
- App Store Connect Analytics（下載、評分）
- TestFlight Feedback（測試反饋）

---

## 🔄 持續維護計畫

### 定期更新
- Bug 修復（2 週一次）
- 功能更新（1 月一次）
- iOS 新版本適配（即時）

### 用戶支援
- 反饋收集渠道
- 常見問題 FAQ
- 用戶教學
- 客服郵箱

---

## 📝 版本規劃

### v1.0.0（首發版本）
- 核心訓練功能
- Apple ID 登入
- 本地數據存儲
- 基礎分析圖表

### v1.1.0（+1 月）
- Firebase 數據同步
- 多設備支援
- 數據雲端備份

### v1.2.0（+2 月）
- 訂閱功能（30天以上數據）
- 進階分析報告
- 自定義訓練計畫

### v2.0.0（+6 月）
- Apple Watch 支援
- 社群功能
- AI 訓練建議

---

## ✅ 檢查清單總結

### 🔴 高優先級（上線前必須）
1. [ ] **版本管理系統**
2. [ ] **Firebase Auth 用戶記錄**
3. [ ] **生產環境 API 配置**
4. [ ] **App Store 資料準備**
5. [ ] **完整測試流程**

### 🟡 中優先級（上線後 1 個月內）
6. [ ] **數據備份機制**
7. [ ] **進階分析事件**
8. [ ] **性能優化**
9. [ ] **錯誤監控強化**

### 🟢 低優先級（未來版本）
10. [ ] **雲端同步**
11. [ ] **訂閱功能**
12. [ ] **Apple Watch**
13. [ ] **社群功能**

---

**最後更新：** 2025-10-29
**負責人：** Mike
**目標上線日期：** TBD

