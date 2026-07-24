# WorkoutRecord(Work It Out)

健身紀錄 app 的單一 context:個人重量訓練的記錄、統計與目標追蹤。

## Language

### 訓練記錄

**訓練(Workout)**:
一次完整的訓練時段,從開始到結束,底下掛多個訓練動作。
_Avoid_: session、workout log

**訓練動作(WorkoutExercise)**:
一次訓練裡針對某個動作的段落,底下掛多個組。
_Avoid_: exercise entry

**組(Set / WorkoutSet)**:
一個訓練動作的一次連續執行:重量 × 次數(可另記 RPE、休息秒數、熱身標記)。
_Avoid_: rep group

**容量(Volume)**:
重量 × 次數的加總,衡量訓練量的核心指標。
_Avoid_: tonnage

### 動作字典

**動作(Exercise)**:
動作字典裡的一個定義(臥推、深蹲…),分內建與自訂兩種。
_Avoid_: movement

**內建動作(System Exercise)**:
App 出廠內建的 66 個動作;跨安裝以「名稱 + 分類」識別,不是以 UUID。

**自訂動作(Custom Exercise)**:
使用者自建的動作,UUID 恆定、屬於該使用者。

**模板(Template)**:
預先排好的動作清單(含建議組數/次數),開新訓練時套用。
_Avoid_: routine、program

### 成就與目標

**個人紀錄(PersonalRecord, PR)**:
某個動作的歷史最佳表現,以估算 1RM 為準。

**三大項紀錄(PowerLiftRecord)**:
深蹲/臥推/硬舉三個項目的 1RM 紀錄,獨立於一般 PR。

**1RM(One-Rep Max)**:
單次能舉起的最大重量,由「重量 × 次數」以公式(如 Epley)估算,非實測。

**目標(UserGoal)**:
使用者設定的週訓練次數與各肌群容量目標。

**體重紀錄(BodyWeight)**:
某個時間點量測的體重,獨立於訓練存在。

### 遷移

**無縫匯入(Seamless Import)**:
使用者從舊 iOS 版升級時,首次啟動自動把舊資料完整搬進新資料庫,全程不遺失、不需使用者操作。
_Avoid_: 資料轉移、migration(保留給 DB schema migration 用)
