# yttoscript

YouTube 影片轉逐字稿。完全免費，不需要任何 API key。

策略：**人工字幕 → 自動字幕 → 本地 Whisper**。有字幕的影片幾秒就好，
沒字幕的才落到 Whisper 轉錄。

## 安裝

```bash
pip install -U yt-dlp faster-whisper
```

另外需要 `ffmpeg`（macOS：`brew install ffmpeg`）。
`faster-whisper` 只有在影片完全沒字幕時才用得到，可以晚點再裝。

## 用法

```bash
./yt2script.sh "https://www.youtube.com/watch?v=VIDEO_ID"
```

```bash
./yt2script.sh "URL" -t -o ~/Documents/transcripts
```

完整選項看 `./yt2script.sh -h`。

## 檔案

| 檔案 | 用途 |
|---|---|
| `yt2script.sh` | 主程式，處理字幕/Whisper 的 fallback 鏈 |
| `vtt2script.py` | 把 VTT/SRT/json3 整理成乾淨逐字稿（含滾動字幕去重） |
| `PROMPT.md` | 同一套流程的 agent prompt 版本，貼給 Claude 就能跑 |

## 關於滾動字幕去重

YouTube 自動字幕每個 cue 會重複上一句再往後接幾個字，直接倒出來會比實際內容
長三到五倍。`vtt2script.py` 會偵測這種前綴成長並收斂，同時剝掉行內時間標記。

## 遇到 "Sign in to confirm you're not a bot"

這是 IP 信譽問題，不是影片的問題：

1. `yt-dlp -U` 升到最新版
2. 加 `-c chrome`（或 firefox / safari / edge / brave）帶瀏覽器 cookie
3. 在雲端機器 / VPS 上跑的話，機房 IP 常被擋 — 改在本機跑

住宅網路基本不會碰到。
