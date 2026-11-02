# YouTube 轉逐字稿 — Agent Prompt

把以下內容整段貼給 Claude Code（或任何能跑 shell 的 agent），後面附上影片連結即可。

---

請把我給的 YouTube 連結轉成繁體中文逐字稿。不論影片有沒有現成字幕都要成功。
全程只用免費工具，不要用任何付費 API 或需要金鑰的服務。

## 環境準備
確認並在缺少時安裝：`yt-dlp`（`pip install -U yt-dlp`，務必是最新版）、`ffmpeg`、
以及 Whisper 備援用的 `faster-whisper`（`pip install -U faster-whisper`）。
把所有中間檔放在暫存目錄，不要弄髒我的專案目錄。

## 流程：照順序試，成功就停，不要跳步

**第 0 步 — 探路**
跑 `yt-dlp --list-subs <URL>`，看清楚這部片有哪些字幕軌、是人工還是自動、
以及原始語言是什麼。先告訴我你看到什麼，再決定抓哪一軌。

**第 1 步 — 人工字幕（品質最好，優先）**
```
yt-dlp --write-subs --sub-langs "zh-TW,zh-Hant,zh-Hans,zh,en" \
  --skip-download -o "%(id)s.%(ext)s" <URL>
```

**第 2 步 — 自動字幕（第 1 步沒東西才做）**
同上但把 `--write-subs` 換成 `--write-auto-subs`。
注意：只抓原生語言那一軌（例如 `zh`），**不要**抓 `xx-zh` 那種「從中文機器翻譯」的軌，
那是二次翻譯，品質差很多。

**第 3 步 — Whisper 本地轉錄（前兩步都沒字幕才做）**
下載音訊後用 faster-whisper 轉，模型用 `large-v3`，開 `vad_filter=True`、`beam_size=5`。
先讓它自動偵測語言並把偵測結果告訴我。
```
yt-dlp -f bestaudio -x --audio-format m4a -o "audio.%(ext)s" <URL>
```
機器記憶體不足時降到 `medium`，並明確告訴我你降級了、品質會略差。

## 遇到 "Sign in to confirm you're not a bot"
這是 IP 信譽問題。依序試：
1. `yt-dlp -U` 升到最新版再試一次
2. 加 `--cookies-from-browser chrome`（或 firefox / safari / edge / brave）
3. 若你跑在雲端機器 / VPS 上，就是機房 IP 被擋，換到本機跑

**絕對不要**為了繞過這個檢查去偽造 client 身分、輪換 user-agent 或用代理池。
三步都失敗就停下來告訴我，不要自己想辦法硬闖。

## 清理字幕（這步最容易被忽略，但很關鍵）
YouTube 自動字幕是「滾動式」的：每個 cue 會重複上一句並往後接幾個字，
直接倒出來會比實際講的內容長三到五倍。必須做：

1. 剝掉所有 HTML 標籤，包含 `<00:00:12.500><c>字</c>` 這種行內時間標記
2. HTML entity 還原（`&amp;` → `&`）
3. **滾動去重**：逐行比對，若當前行以前一行為開頭（前綴成長），就用當前行取代前一行；
   完全相同則丟棄；前一行以當前行為開頭也丟棄
4. 依「停頓 ≥ 3 秒」或「累積約 400 字」斷段，讓它可讀

## 輸出
寫成 `transcripts/<影片標題>.md`，開頭是 `# 標題` 和來源連結，正文分段。
另外給我一個時間戳版本（每段前面加 `**[m:ss]**`）。
簡體內容請轉成繁體用字。不要改寫、不要摘要、不要潤稿——逐字稿就是逐字稿。

做完回報：用了哪一步拿到的（人工字幕 / 自動字幕 / Whisper）、
偵測到的語言、總段數、檔案路徑。如果有任何降級或妥協，明講。

影片連結：<把連結貼在這裡>
