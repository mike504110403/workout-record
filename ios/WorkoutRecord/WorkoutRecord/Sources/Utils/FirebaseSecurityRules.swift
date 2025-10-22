import Foundation

/// Firebase 安全規則
struct FirebaseSecurityRules {
    
    /// Firestore 安全規則
    static let firestoreRules = """
    rules_version = '2';
    service cloud.firestore {
      match /databases/{database}/documents {
        // 分析會話集合 - 只允許寫入，不允許讀取
        match /analytics_sessions/{sessionId} {
          allow write: if request.auth == null; // 匿名寫入
          allow read: if false; // 禁止讀取
        }
        
        // 分析事件集合 - 只允許寫入，不允許讀取
        match /analytics_events/{eventId} {
          allow write: if request.auth == null; // 匿名寫入
          allow read: if false; // 禁止讀取
        }
        
        // 用戶行為集合 - 只允許寫入，不允許讀取
        match /user_behavior/{behaviorId} {
          allow write: if request.auth == null; // 匿名寫入
          allow read: if false; // 禁止讀取
        }
        
        // 其他所有文檔 - 禁止訪問
        match /{document=**} {
          allow read, write: if false;
        }
      }
    }
    """
    
    /// Storage 安全規則（如果使用 Firebase Storage）
    static let storageRules = """
    rules_version = '2';
    service firebase.storage {
      match /b/{bucket}/o {
        // 禁止所有訪問
        match /{allPaths=**} {
          allow read, write: if false;
        }
      }
    }
    """
    
    /// 獲取安全規則說明
    static func getSecurityRulesInfo() -> String {
        return """
        Firebase 安全規則說明：
        
        1. 分析數據集合：
           - analytics_sessions: 會話數據
           - analytics_events: 事件數據
           - user_behavior: 用戶行為數據
        
        2. 權限設定：
           - 允許匿名寫入（用於數據收集）
           - 禁止讀取（保護用戶隱私）
           - 禁止其他所有訪問
        
        3. 部署方式：
           - 在 Firebase Console 中複製規則
           - 在 Firestore 規則編輯器中貼上
           - 點擊「發布」按鈕
        """
    }
}
