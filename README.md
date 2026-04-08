# EdgeTX Lua Scripts (B/W & Color Screen)

EdgeTX Lua スクリプト集です。Radiomaster Boxer（128×64 白黒液晶）および **RadioMaster TX15 MAX（480×272 カラー液晶）** に対応しています。

A growing collection of **EdgeTX Lua scripts** for Radiomaster, Jumper, and other OpenTX/EdgeTX radios.  
Scripts support both **black-and-white displays** (Radiomaster Boxer 128×64) and **color touch displays** (TX15 MAX / TX16S Mark II 480×272).

## 📂 リポジトリ構成 / Repository Structure

```
SCRIPTS/
├── TOOLS/        # SYS → Tools メニューから起動するツール
├── MIXES/        # 機体ごとのスクリプト
└── TELEMETRY/    # テレメトリー画面スクリプト
```

`SCRIPTS` フォルダをSDカードのルートにコピーしてください。  
Copy the `SCRIPTS` folder directly to your radio's **SD card root**.

---

## 📜 スクリプト一覧 / Available Scripts

### 1. [ELRS_Finder.lua](SCRIPTS/TOOLS/ELRS_Finder.lua)

**種別 / Type:** Tool (`/SCRIPTS/TOOLS/`)

#### 概要 / Overview

ELRS/CRSFテレメトリーを使った**ロスト機体の方向探知ツール**です。  
An **RSSI-based lost-model finder** using ELRS/CRSF telemetry.

プロポを持って歩き回り、**右パネルの逆ピラミッドが大きくなる方向**に進むとドローンに近づいています。  
Walk around with your radio — move in the direction that **grows the inverted pyramid** on the right panel.

#### 対応機種 / Supported Radios

| ラジオ | 画面 | 表示 |
|---|---|---|
| Radiomaster Boxer | 128×64 白黒 | テキスト表示（バー＋強度） |
| RadioMaster TX15 MAX | 480×272 カラー | 2パネル表示（左: 数値、右: 逆ピラミッド） |
| RadioMaster TX16S Mark II | 480×272 カラー | 2パネル表示（左: 数値、右: 逆ピラミッド） |

#### TX15 MAX 画面レイアウト / TX15 MAX Screen Layout

```
┌────────────────────┬───────────────────────┐
│ ELRS Finder        │       TREND           │
│                    │                       │
│ Src:dBm Raw:-65.3  │   ███████████████     │ ← 5本=最大
│                    │      ████████         │
│ Strength: 72%      │        ████           │
│ [==========  ]     │         ██            │
│                    │          █            │
│ Avg: -67.2 dBm     │                       │
│ Peak: 80%          │  Peak: 80%            │
│ Gap:  -8%          │  [============  ]     │
│                    │  Now:  72%            │
│ ENT: reset peak    │  [=========    ]      │
│ Walk & watch       │                       │
│ 5 bars = max       │                       │
└────────────────────┴───────────────────────┘
```

#### ピラミッドの見方 / How to Read the Pyramid

| バー数 | 意味 |
|---|---|
| **5本（最大）** | **近づいている** / そのまま進め！ |
| 3本 | 安定・静止している |
| 1〜2本 | 遠ざかっている |
| **0本** | **大きく離れた** / 引き返せ！ |

ピラミッドは「**現在の強度 − ピーク強度**」の差（Gap）で動きます。  
近づいて新しいピークを更新し続けているとき → 常に5本  
ピークから離れるほど → バーが減少

#### 信号スケール / Signal Scale

| 距離 (目安) | 強度 (%) |
|---|---|
| 〜50cm | 100% |
| 〜1m | 約82% |
| 〜2m | 約64% |
| 遠距離 | 0〜40% |

※ アンテナの向きや環境によって変わります。

#### 操作方法 / Controls

| 操作 | 動作 |
|---|---|
| `ENT` キー | ピーク・履歴をリセット |
| 自動 | 起動時に最初の受信値から計測開始 |

#### インストール / Installation

1. `ELRS_Finder.lua` を SDカードの `/SCRIPTS/TOOLS/` にコピー
2. プロポで: `SYS` 長押し → **Tools** タブ → **ELRS Finder** を実行
3. 推奨設定: ELRSメニューで**送信出力を固定低出力**（10〜25mW）に設定

#### 技術仕様 / Technical Details

- テレメトリーソース: `1RSS`（RSSI dBm）→ `RSNR`（SNR）→ `RQly`（LQ）の順にフォールバック
- 信号スムージング: EMA α=0.50（高速追従）
- ピークとの差分でピラミッドバー数を決定（Gap閾値: -3/-8/-18/-35/-55%）
- ガイガーカウンター風ビープ音: 強度が高いほど速く鳴動

---

### 2. [FieldNotes.lua](SCRIPTS/TOOLS/FieldNotes.lua)

**種別 / Type:** Tool (`/SCRIPTS/TOOLS/`)

#### 概要 / Overview

フライト情報をプロポから直接記録する**簡易ログツール**です。  
A **quick flight logging tool** for recording details directly from your radio.

- パック番号・状態、プロペラ種類・状態、飛行メモを記録
- `/LOGS/fieldnotes.txt` にタイムスタンプ付きで保存
- 保存後に自動終了

#### インストール / Installation

1. `FieldNotes.lua` を `/SCRIPTS/TOOLS/` にコピー
2. `SYS` 長押し → **Tools** → **Field Notes** を実行
3. 編集後、`[ Save ]` を選択して保存

**ログファイル例:**
```
2025-08-16 05:44 | Pack: 3 (Bad) | Prop: 5146 (Chipped) | Note: Wobbly
2025-08-16 05:58 | Pack: 4 (Good) | Prop: 5040 (New) | Note: Smooth
```

---

## 📥 インストール（全スクリプト共通）/ General Installation

1. このリポジトリをダウンロード:
   - **方法A:** 緑の **Code** ボタン → **Download ZIP**
   - **方法B:** `git clone` でクローン
2. `SCRIPTS` フォルダをSDカードのルートにコピー
3. スクリプトの起動場所:
   - `/SCRIPTS/TOOLS/` → **Tools メニュー**
   - `/SCRIPTS/MIXES/` → **モデルスクリプト**
   - `/SCRIPTS/TELEMETRY/` → **テレメトリー画面**

---

## 📄 ライセンス / License

[MIT License](LICENSE) — 自由に使用・改変・配布できます。クレジット表記をお願いします。  
Feel free to use, modify, and share — please credit this repository.

---

✈️ **More scripts coming soon!** / 新しいスクリプトを追加予定です！
