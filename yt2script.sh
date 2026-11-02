#!/usr/bin/env bash
# yt2script — YouTube 影片轉逐字稿，完全免費、不需任何 API key。
#
#   字幕優先：人工字幕 -> 自動字幕 -> (都沒有才) 本地 Whisper 轉錄
#
# 用法：
#   ./yt2script.sh <YouTube URL> [選項]
#
# 選項：
#   -l, --lang LANGS     字幕語言優先序 (預設 zh-TW,zh-Hant,zh-Hans,zh,en)
#   -o, --outdir DIR     輸出目錄 (預設 ./transcripts)
#   -t, --timestamps     逐字稿加上 [m:ss] 時間戳
#   -c, --cookies BROWSER  從瀏覽器帶 cookie (chrome/firefox/safari/edge/brave)
#                          — 遇到 "Sign in to confirm you're not a bot" 就加這個
#   -w, --whisper        跳過字幕，直接用 Whisper 轉錄
#   -m, --model NAME     Whisper 模型 (預設 large-v3；小一點用 medium / small)
#   -k, --keep           保留中間檔 (.vtt / .m4a)
#   -h, --help           顯示本說明

set -euo pipefail

LANGS="zh-TW,zh-Hant,zh-Hans,zh,en"
OUTDIR="./transcripts"
TIMESTAMPS=""
COOKIES=""
FORCE_WHISPER=0
MODEL="large-v3"
KEEP=0
URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--lang)       LANGS="$2"; shift 2 ;;
    -o|--outdir)     OUTDIR="$2"; shift 2 ;;
    -t|--timestamps) TIMESTAMPS="--timestamps"; shift ;;
    -c|--cookies)    COOKIES="$2"; shift 2 ;;
    -w|--whisper)    FORCE_WHISPER=1; shift ;;
    -m|--model)      MODEL="$2"; shift 2 ;;
    -k|--keep)       KEEP=1; shift ;;
    -h|--help)       awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; exit 0 ;;
    -*)              echo "unknown option: $1" >&2; exit 2 ;;
    *)               URL="$1"; shift ;;
  esac
done

[[ -n "$URL" ]] || { echo "用法：$0 <YouTube URL> [選項]   (-h 看說明)" >&2; exit 2; }
command -v yt-dlp >/dev/null || { echo "缺 yt-dlp：pip install -U yt-dlp" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT="$HERE/vtt2script.py"
[[ -f "$CONVERT" ]] || { echo "找不到 $CONVERT" >&2; exit 1; }

mkdir -p "$OUTDIR"
WORK="$(mktemp -d)"
cleanup() { [[ $KEEP -eq 1 ]] || rm -rf "$WORK"; }
trap cleanup EXIT

YTDLP=(yt-dlp --no-warnings --no-playlist)
[[ -n "$COOKIES" ]] && YTDLP+=(--cookies-from-browser "$COOKIES")

echo "==> 讀取影片資訊"
ID="$("${YTDLP[@]}" --print "%(id)s" "$URL" | head -1)"
TITLE="$("${YTDLP[@]}" --print "%(title)s" "$URL" | head -1)"
echo "    $TITLE  [$ID]"

SLUG="$(printf '%s' "$TITLE" | tr -cd '[:alnum:][:space:]_.-' | tr ' ' '_' | cut -c1-80)"
[[ -n "$SLUG" ]] || SLUG="$ID"
OUT="$OUTDIR/${SLUG}.md"

SUB=""
if [[ $FORCE_WHISPER -eq 0 ]]; then
  # 人工字幕品質遠高於自動字幕，所以分兩輪試。
  for pass in manual auto; do
    echo "==> 嘗試${pass/manual/人工}${pass/auto/自動}字幕 ($LANGS)"
    FLAG="--write-subs"; [[ $pass == auto ]] && FLAG="--write-auto-subs"
    "${YTDLP[@]}" $FLAG --sub-langs "$LANGS" --skip-download \
      -o "$WORK/%(id)s.%(ext)s" "$URL" >/dev/null 2>&1 || true
    SUB="$(find "$WORK" -maxdepth 1 \( -name '*.vtt' -o -name '*.srt' -o -name '*.json3' \) | sort | head -1)"
    [[ -n "$SUB" ]] && { echo "    找到：$(basename "$SUB")"; break; }
  done
fi

if [[ -z "$SUB" ]]; then
  echo "==> 沒有字幕，改用本地 Whisper ($MODEL)"
  command -v ffmpeg >/dev/null || { echo "缺 ffmpeg，請先安裝" >&2; exit 1; }
  python3 -c "import faster_whisper" 2>/dev/null || {
    echo "缺 faster-whisper：pip install -U faster-whisper" >&2; exit 1; }

  echo "    下載音訊"
  "${YTDLP[@]}" -f "bestaudio/best" -x --audio-format m4a \
    -o "$WORK/audio.%(ext)s" "$URL"
  AUDIO="$(find "$WORK" -maxdepth 1 -name 'audio.*' | head -1)"
  [[ -n "$AUDIO" ]] || { echo "音訊下載失敗" >&2; exit 1; }

  echo "    轉錄中（第一次會先下載模型，請耐心等）"
  MODEL="$MODEL" AUDIO="$AUDIO" WORK="$WORK" python3 - <<'PY'
import os
from faster_whisper import WhisperModel

model = WhisperModel(os.environ["MODEL"], device="auto", compute_type="auto")
segments, info = model.transcribe(os.environ["AUDIO"], vad_filter=True, beam_size=5)
print(f"    偵測語言：{info.language} (信心 {info.language_probability:.2f})")


def srt_time(t):
    h, rem = divmod(int(t), 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d},{int((t % 1) * 1000):03d}"


with open(os.path.join(os.environ["WORK"], "whisper.srt"), "w", encoding="utf-8") as fh:
    for i, seg in enumerate(segments, 1):
        text = seg.text.strip()
        if text:
            fh.write(f"{i}\n{srt_time(seg.start)} --> {srt_time(seg.end)}\n{text}\n\n")
PY
  SUB="$WORK/whisper.srt"
fi

echo "==> 整理逐字稿"
python3 -I "$CONVERT" "$SUB" -o "$OUT" $TIMESTAMPS \
  --title "$TITLE" --url "https://www.youtube.com/watch?v=$ID"

echo "==> 完成：$OUT"
[[ $KEEP -eq 1 ]] && echo "    中間檔保留在 $WORK"
