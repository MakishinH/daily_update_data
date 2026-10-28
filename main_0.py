import os
import json
from datetime import datetime, timezone
import yfinance as yf

# 輸出檔案名稱（存放在 GitHub 儲存庫根目錄）
JSON_FILENAME = "daily_update.json"

# 定義要抓取的目標清單
TARGET_SYMBOLS = {
    "^DJI": "道瓊工業指數",
    "^GSPC": "S&P 500 指數",
    "^IXIC": "NASDAQ 指數",
    "^SOXX": "費城半導體 指數",   #原code "SOXX": "iShares 費城半導體 ETF",
    "^N225": "日經 225 指數",   #原"VOO": "Vanguard S&P 500 ETF",
    "^KS11": "韓國綜合股價指數", #原"QQQ": "Invesco QQQ Trust",
    "TSM": "台積電 ADR",
    "NVDA": "輝達",
    "AAPL": "蘋果",
    "TSLA": "特斯拉",
    "SPCX": "太空探索",
    "AVGO": "博通",
    "AMD": "超微",
    "GOOGL": "Google",
    "META": "Meta",
    "AMZN": "亞馬遜",
    "BRK-B": "波克夏",
    "^TWII": "台股加權指數",
    "0050.TW": "元大台灣50",
    "00631L.TW": "元大50正2"
}

def fetch_market_data():
    """抓取市場數據的核心函式，內建個別標的容錯機制"""
    market_data = {}
    current_time_str = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    
    for symbol, name in TARGET_SYMBOLS.items():
        try:
            ticker = yf.Ticker(symbol)
            info = ticker.fast_info
            
            current_price = info.last_price
            prev_close = info.previous_close
            
            if current_price is not None and prev_close is not None and prev_close != 0:
                change = current_price - prev_close
                change_percent = (change / prev_close) * 100
                
                market_data[symbol] = {
                    "name": name,
                    "price": round(current_price, 2),
                    "change": round(change, 2),
                    "changePercent": round(change_percent, 2),
                    "previousClose": round(prev_close, 2),
                    "updatedAt": current_time_str
                }
                print(f"✅ 成功抓取: {name} ({symbol}) - 現價: {round(current_price, 2)}")
            else:
                print(f"⚠️ 警告: {symbol} 缺少價格數據，略過該標的。")
        except Exception as e:
            # 單一標的抓取失敗不中斷整體執行
            print(f"❌ 抓取 {name} ({symbol}) 發生錯誤: {e}，跳過處理。")
            continue
            
    return market_data

def save_to_local(json_data_str, filename):
    """將 JSON 字串寫入本地檔案供 GitHub Actions 提交"""
    with open(filename, "w", encoding="utf-8") as f:
        f.write(json_data_str)
    print(f"📦 成功產出檔案: {os.path.abspath(filename)}")

if __name__ == "__main__":
    print(f"[{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}] 開始更新市場數據...")
    data = fetch_market_data()
    
    if not data:
        raise RuntimeError("所有標的皆未能成功抓取數據，終止產出。")
        
    json_output = json.dumps(data, ensure_ascii=False, indent=2)
    save_to_local(json_output, JSON_FILENAME)
    print("🎉 資料更新完畢！")
