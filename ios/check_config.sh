#!/bin/bash

# WorkoutRecord 配置檢查腳本
# 用於檢查上線前的所有配置是否完整

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 WorkoutRecord 配置檢查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PROJECT_DIR="/Users/mike/Documents/self/workout-record/ios/WorkoutRecord/WorkoutRecord"
ERRORS=0
WARNINGS=0

# 顏色定義
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 檢查函數
check_file() {
    local file=$1
    local description=$2
    
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description - 檔案不存在: $file"
        ((ERRORS++))
        return 1
    fi
}

check_directory() {
    local dir=$1
    local description=$2
    
    if [ -d "$dir" ]; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${RED}✗${NC} $description - 目錄不存在: $dir"
        ((ERRORS++))
        return 1
    fi
}

check_content() {
    local file=$1
    local pattern=$2
    local description=$3
    
    if [ -f "$file" ] && grep -q "$pattern" "$file"; then
        echo -e "${GREEN}✓${NC} $description"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $description - 可能需要配置"
        ((WARNINGS++))
        return 1
    fi
}

echo "1️⃣  檢查核心服務檔案"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file "$PROJECT_DIR/Sources/Services/VersionManager.swift" "版本管理服務"
check_file "$PROJECT_DIR/Sources/Services/FirebaseAuthService.swift" "Firebase 認證服務"
check_file "$PROJECT_DIR/Sources/Services/AnalyticsService.swift" "分析服務"
check_file "$PROJECT_DIR/Sources/Services/EnvironmentConfig.swift" "環境配置"
check_file "$PROJECT_DIR/Sources/Services/CoreDataBackupService.swift" "備份服務"
echo ""

echo "2️⃣  檢查 UI 元件"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_file "$PROJECT_DIR/Sources/Views/Update/UpdateView.swift" "更新視圖"
check_file "$PROJECT_DIR/Sources/Views/Auth/AppleIDLoginView.swift" "登入視圖"
check_file "$PROJECT_DIR/Sources/Utils/UIInteractionTracker.swift" "UI 互動追蹤"
echo ""

echo "3️⃣  檢查 Firebase 配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if check_file "$PROJECT_DIR/GoogleService-Info.plist" "GoogleService-Info.plist"; then
    echo -e "   ${BLUE}ℹ${NC} 請確認使用的是正確環境的配置檔案"
    echo -e "   ${BLUE}ℹ${NC} Development: 開發環境"
    echo -e "   ${BLUE}ℹ${NC} Production: 生產環境（上架前替換）"
fi
echo ""

echo "4️⃣  檢查 Assets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_directory "$PROJECT_DIR/Assets.xcassets/AppIcon.appiconset" "App Icon"
check_file "$PROJECT_DIR/Assets.xcassets/AppIcon.appiconset/Contents.json" "App Icon Contents"
check_file "$PROJECT_DIR/Assets.xcassets/AccentColor.colorset/Contents.json" "Accent Color"
echo ""

echo "5️⃣  檢查必要配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 檢查 Info.plist
INFO_PLIST="../WorkoutRecord/Info.plist"
if [ -f "$INFO_PLIST" ]; then
    echo -e "${GREEN}✓${NC} Info.plist 存在"
    
    # 檢查必要的權限描述
    if /usr/libexec/PlistBuddy -c "Print :NSAppleSignInUsageDescription" "$INFO_PLIST" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Apple Sign In 權限已配置"
    else
        echo -e "${YELLOW}⚠${NC} Apple Sign In 權限未配置"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗${NC} Info.plist 不存在"
    ((ERRORS++))
fi
echo ""

echo "6️⃣  檢查未完成的 TODO"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TODO_COUNT=$(find "$PROJECT_DIR/Sources" -name "*.swift" -exec grep -n "TODO\|FIXME" {} + 2>/dev/null | wc -l | tr -d ' ')
if [ "$TODO_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠${NC} 發現 $TODO_COUNT 個 TODO/FIXME"
    echo -e "   ${BLUE}ℹ${NC} 執行以下命令查看詳情:"
    echo -e "   grep -rn \"TODO\\|FIXME\" $PROJECT_DIR/Sources"
    ((WARNINGS++))
else
    echo -e "${GREEN}✓${NC} 沒有未完成的 TODO"
fi
echo ""

echo "7️⃣  檢查 Build Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
PBXPROJ="../WorkoutRecord.xcodeproj/project.pbxproj"
if [ -f "$PBXPROJ" ]; then
    echo -e "${GREEN}✓${NC} Xcode 專案檔案存在"
    
    if grep -q "SWIFT_ACTIVE_COMPILATION_CONDITIONS.*DEBUG" "$PBXPROJ"; then
        echo -e "${GREEN}✓${NC} Debug 編譯條件已配置"
    else
        echo -e "${YELLOW}⚠${NC} Debug 編譯條件未配置"
        ((WARNINGS++))
    fi
else
    echo -e "${RED}✗${NC} Xcode 專案檔案不存在"
    ((ERRORS++))
fi
echo ""

echo "8️⃣  建議的配置檢查"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${YELLOW}⚠${NC} 以下項目需要手動確認:"
echo "   □ Bundle Identifier 已設置且正確"
echo "   □ Signing & Capabilities 已配置"
echo "   □ Sign in with Apple 已啟用"
echo "   □ Firebase Remote Config 已設置"
echo "   □ App Store Connect 已準備"
echo "   □ 截圖和 App 描述已準備"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 檢查結果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${RED}錯誤: $ERRORS${NC}"
echo -e "${YELLOW}警告: $WARNINGS${NC}"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ 所有檢查通過！準備上線！${NC}"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠️  有 $WARNINGS 個警告，請檢查後再上線${NC}"
    exit 0
else
    echo -e "${RED}❌ 有 $ERRORS 個錯誤，必須修復後才能上線${NC}"
    exit 1
fi

