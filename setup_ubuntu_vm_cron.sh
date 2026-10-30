#!/usr/bin/env bash
# ==============================================================================
# 🚀 Ubuntu VM 準點喚醒 GitHub Actions 排程安裝腳本 (setup_ubuntu_vm_cron.sh)
# ==============================================================================
# 功能說明：
#   解決 GitHub Actions 原生 schedule (cron) 延遲 5~6 小時的問題。
#   透過 Ubuntu VM 的 crontab 在台北時間 (Asia/Taipei) 指定分秒發送輕量級
#   GitHub REST API (workflow_dispatch) 喚醒信號，使雲端 Workflow 於 2 秒內立即啟動！
#   同時搭配各倉庫 .yml 內的「防重複保底檢查」，確保平時 100% 準時、絕不重複跑兩次。
#
# 使用方式 (在 Ubuntu VM 終端機執行)：
#   bash setup_ubuntu_vm_cron.sh <您的_GITHUB_PAT_TOKEN>
# ==============================================================================

set -e

GH_TOKEN="${1:-}"
if [ -z "$GH_TOKEN" ]; then
    read -r -p "🔑 請輸入您的 GitHub Personal Access Token (具備 repo / workflow 權限): " GH_TOKEN
fi

if [ -z "$GH_TOKEN" ]; then
    echo "❌ 錯誤：未提供 GitHub Token，安裝中止。"
    exit 1
fi

# 1. 設定 Ubuntu VM 系統時區為台北時間 (Asia/Taipei)
echo "🌏 [1/4] 正在確認並設定系統時區為 Asia/Taipei (UTC+8)..."
if command -v timedatectl >/dev/null 2>&1; then
    sudo timedatectl set-timezone Asia/Taipei 2>/dev/null || true
fi
echo "   目前系統時間: $(TZ=Asia/Taipei date '+%Y-%m-%d %H:%M:%S %Z')"

# 2. 安全儲存 GitHub Token (權限 600 僅當前使用者可讀)
TOKEN_FILE="$HOME/.github_dispatch_token"
echo "$GH_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"
echo "🔒 [2/4] 已安全儲存授權 Token 至 $TOKEN_FILE (chmod 600)"

# 3. 建立通用觸發腳本 ~/.local/bin/trigger_github_workflow.sh
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
TRIGGER_SCRIPT="$BIN_DIR/trigger_github_workflow.sh"
LOG_FILE="$HOME/github_dispatch_cron.log"

cat << 'EOF' > "$TRIGGER_SCRIPT"
#!/usr/bin/env bash
# 參數 1: 儲存庫名稱 (例如 MakishinH/KGI_API_BuySell)
# 參數 2: Workflow 檔名 (例如 daily_v7_signal.yml)
# 參數 3: 任務說明標籤

REPO="$1"
WORKFLOW="$2"
LABEL="${3:-$REPO/$WORKFLOW}"
TOKEN_FILE="$HOME/.github_dispatch_token"
LOG_FILE="$HOME/github_dispatch_cron.log"

if [ ! -f "$TOKEN_FILE" ]; then
    echo "[$(TZ=Asia/Taipei date '+%Y-%m-%d %H:%M:%S')] ❌ 找不到 $TOKEN_FILE" >> "$LOG_FILE"
    exit 1
fi

GH_TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
NOW_STR=$(TZ=Asia/Taipei date '+%Y-%m-%d %H:%M:%S')

HTTP_CODE=$(curl -sS -o /tmp/gh_dispatch_resp.txt -w "%{http_code}" \
  -X POST \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPO}/actions/workflows/${WORKFLOW}/dispatches" \
  -d '{"ref":"main"}')

if [ "$HTTP_CODE" = "204" ]; then
    echo "[${NOW_STR}] ✅ 成功準點喚醒 [${LABEL}] (${REPO} -> ${WORKFLOW}) [HTTP 204]" >> "$LOG_FILE"
else
    ERR_MSG=$(cat /tmp/gh_dispatch_resp.txt 2>/dev/null | tr '\n' ' ')
    echo "[${NOW_STR}] ⚠️ 喚醒失敗 [${LABEL}] (${REPO} -> ${WORKFLOW}) [HTTP ${HTTP_CODE}]: ${ERR_MSG}" >> "$LOG_FILE"
fi
EOF

chmod +x "$TRIGGER_SCRIPT"
echo "⚙️  [3/4] 已建立觸發執行檔: $TRIGGER_SCRIPT"

# 4. 寫入 Crontab 排程 (自動移除舊區塊並寫入最新 5 組準點排程)
CRON_BEGIN="# >>> ANTIGRAVITY_GITHUB_DISPATCH_START >>>"
CRON_END="# <<< ANTIGRAVITY_GITHUB_DISPATCH_END <<<"

EXISTING_CRON=$(crontab -l 2>/dev/null || true)
CLEAN_CRON=$(echo "$EXISTING_CRON" | awk "
  /$CRON_BEGIN/ { skip=1; next }
  /$CRON_END/ { skip=0; next }
  !skip { print }
")

NEW_CRON_BLOCK=$(cat << EOF
$CRON_BEGIN
CRON_TZ=Asia/Taipei
TZ=Asia/Taipei
# 1. 週一至週六 07:00 - 即時市場指數與 ETF (美股收盤與全球指數)
0 7 * * 1-6 $TRIGGER_SCRIPT "MakishinH/daily_update_data" "Daily_update_data.yml" "07:00_Market_Index"
# 2. 週一至週五 08:25 - AI CFO 早安晨會簡報 & Telegram 推播
25 8 * * 1-5 $TRIGGER_SCRIPT "MakishinH/Daily-AI-CFO-Telegram-Bot" "daily_ai_cfo_main6.yml" "08:25_Daily_AI_CFO"
# 3. 週一至週五 17:00 - Stock_Agent 台股量化波段盤後訊號
0 17 * * 1-5 $TRIGGER_SCRIPT "MakishinH/Stock_Agent" "daily_tw_signals.yml" "17:00_Stock_Agent"
# 4. 週一至週五 18:00 - 台指期 V7 終極王者版 長線波段與正金字塔訊號
0 18 * * 1-5 $TRIGGER_SCRIPT "MakishinH/KGI_API_BuySell" "daily_v7_signal.yml" "18:00_KGI_V7_Signal"
# 5. 週一至週五 22:00 - 即時市場指數與 ETF (美股開盤即時行情)
0 22 * * 1-5 $TRIGGER_SCRIPT "MakishinH/daily_update_data" "Daily_update_data.yml" "22:00_Market_Index"
$CRON_END
EOF
)

printf "%s\n%s\n" "$CLEAN_CRON" "$NEW_CRON_BLOCK" | sed '/^$/N;/^\n$/D' | crontab -

echo "✅ [4/4] 已成功將 5 組準點喚醒任務註冊至 Ubuntu Crontab！"
echo "------------------------------------------------------------------------------"
crontab -l | sed -n "/$CRON_BEGIN/,/$CRON_END/p"
echo "------------------------------------------------------------------------------"
echo "📄 執行日誌路徑: $LOG_FILE"
echo "🧪 若要立即測試喚醒台指期 V7 排程，可執行："
echo "   $TRIGGER_SCRIPT \"MakishinH/KGI_API_BuySell\" \"daily_v7_signal.yml\" \"Manual_Test\" && tail -n 5 $LOG_FILE"
