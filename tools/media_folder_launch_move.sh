#!/bin/bash
# 真实进程级：用构建出的 Replay 二进制加 --move-media-folder，在临时家目录搬 3 个小文件。
# SPM 可执行文件的偏好域是 Replay，不是打包应用的 com.mg.replay。
# 成功一次，再刻意造冲突失败一次。不碰真实片库。
set -euo pipefail

binary="${1:-}"
if [[ -z "$binary" || ! -x "$binary" ]]; then
    echo "用法: $0 <Replay二进制>" >&2
    exit 2
fi

real_movies="$HOME/Movies/Replay"
existing_pref=$(defaults read Replay MediaFolderPath 2>/dev/null || true)
if [[ -n "$existing_pref" && ( "$existing_pref" == "$real_movies" || "$existing_pref" == /Volumes/* ) ]]; then
    echo "拒绝：Replay 偏好域已指向真实片库 $existing_pref" >&2
    exit 3
fi
# 清掉上次实测残留，让 CFFIXED_USER_HOME 下的 ~/Movies/Replay 成为源。
defaults delete Replay MediaFolderPath 2>/dev/null || true

work=$(mktemp -d /tmp/seesee-launch-move.XXXXXX)
home="$work/home"
source_dir="$home/Movies/Replay"
dest_ok="$work/dest-ok"
dest_fail="$work/dest-fail"
support="$home/Library/Application Support/Replay"
prefs="$home/Library/Preferences"
id1="11111111-1111-1111-1111-111111111111"
id2="22222222-2222-2222-2222-222222222222"
id3="33333333-3333-3333-3333-333333333333"

cleanup() {
    if [[ -n "${app_pid:-}" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    defaults delete Replay MediaFolderPath 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "$source_dir" "$support" "$prefs" "$dest_ok" "$dest_fail"
printf 'video-one-bytes\n' > "$source_dir/${id1}.mp4"
printf 'video-two-bytes\n' > "$source_dir/${id2}.mp4"
printf 'video-three-bytes\n' > "$source_dir/${id3}.mp4"
hash1=$(/usr/bin/shasum -a 256 "$source_dir/${id1}.mp4" | awk '{print $1}')
hash2=$(/usr/bin/shasum -a 256 "$source_dir/${id2}.mp4" | awk '{print $1}')
hash3=$(/usr/bin/shasum -a 256 "$source_dir/${id3}.mp4" | awk '{print $1}')

write_queue() {
    python3 - "$support/queue.json" "$source_dir" "$id1" "$id2" "$id3" <<'PY'
import json, sys
path, folder, *ids = sys.argv[1:]
items = []
for index, item_id in enumerate(ids, start=1):
    items.append({
        "id": item_id,
        "urlString": f"https://example.com/{index}",
        "title": f"视频{index}",
        "author": "launch",
        "duration": 10,
        "addedAt": "2024-01-01T00:00:00Z",
        "state": "ready",
        "progress": 1,
        "progressLabel": "已下载",
        "localFilePath": f"{folder}/{item_id}.mp4",
    })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(items, handle)
PY
}

write_queue
cp "$support/queue.json" "$work/queue.before.json"

if [[ "$source_dir" == "$real_movies" || "$dest_ok" == "$real_movies" ]]; then
    echo "拒绝：路径落到了真实片库" >&2
    exit 3
fi

file_hash() {
    /usr/bin/shasum -a 256 "$1" | awk '{print $1}'
}

run_move() {
    local dest="$1"
    local log="$2"
    local until_source_gone="${3:-0}"
    CFFIXED_USER_HOME="$home" HOME="$home" \
        "$binary" --move-media-folder "$dest" >"$log" 2>&1 &
    app_pid=$!
    local waited=0
    local limit=15
    if [[ "$until_source_gone" != "1" ]]; then
        limit=6
    fi
    while kill -0 "$app_pid" 2>/dev/null && [[ $waited -lt $limit ]]; do
        sleep 1
        waited=$((waited + 1))
        if [[ "$until_source_gone" == "1" \
            && -f "$dest/${id1}.mp4" && -f "$dest/${id2}.mp4" && -f "$dest/${id3}.mp4" \
            && ! -f "$source_dir/${id1}.mp4" && ! -f "$source_dir/${id2}.mp4" && ! -f "$source_dir/${id3}.mp4" ]]; then
            sleep 1
            break
        fi
    done
    sleep 1
    if kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    app_pid=""
}

echo "=== 成功搬移 ==="
run_move "$dest_ok" "$work/success.log" 1

test -f "$dest_ok/${id1}.mp4"
test -f "$dest_ok/${id2}.mp4"
test -f "$dest_ok/${id3}.mp4"
test ! -f "$source_dir/${id1}.mp4"
test ! -f "$source_dir/${id2}.mp4"
test ! -f "$source_dir/${id3}.mp4"
test "$(file_hash "$dest_ok/${id1}.mp4")" = "$hash1"
test "$(file_hash "$dest_ok/${id2}.mp4")" = "$hash2"
test "$(file_hash "$dest_ok/${id3}.mp4")" = "$hash3"
python3 - "$support/queue.json" "$dest_ok" "$id1" "$id2" "$id3" <<'PY'
import json, sys
path, dest, *ids = sys.argv[1:]
items = json.load(open(path, encoding="utf-8"))
got = {item["id"]: item["localFilePath"] for item in items}
for item_id in ids:
    expected = f"{dest}/{item_id}.mp4"
    actual = got[item_id]
    if actual != expected:
        raise SystemExit(f"queue 路径未改写: {item_id} {actual} != {expected}")
PY
backup=$(ls "$support"/queue.json.bak-* 2>/dev/null | head -n 1)
test -n "$backup"
test -f "$backup"
test ! -f "$support/media-folder-move.inprogress"
pref=$(defaults read Replay MediaFolderPath)
test "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$pref")" = "$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dest_ok")"
echo "success dest=$dest_ok backup=$backup pref=$pref marker=cleared"

echo "=== 冲突失败回滚 ==="
mkdir -p "$source_dir"
printf 'video-one-bytes\n' > "$source_dir/${id1}.mp4"
printf 'video-two-bytes\n' > "$source_dir/${id2}.mp4"
printf 'video-three-bytes\n' > "$source_dir/${id3}.mp4"
write_queue
cp "$support/queue.json" "$work/queue.fail-before.json"
defaults delete Replay MediaFolderPath 2>/dev/null || true
printf 'different-existing\n' > "$dest_fail/${id1}.mp4"
run_move "$dest_fail" "$work/fail.log" 0

test -f "$source_dir/${id1}.mp4"
test -f "$source_dir/${id2}.mp4"
test -f "$source_dir/${id3}.mp4"
printf 'video-one-bytes\n' | cmp -s - "$source_dir/${id1}.mp4"
printf 'different-existing\n' | cmp -s - "$dest_fail/${id1}.mp4"
test ! -f "$dest_fail/${id2}.mp4"
test ! -f "$dest_fail/${id3}.mp4"
python3 - "$support/queue.json" "$work/queue.fail-before.json" <<'PY'
import json, sys
after = json.load(open(sys.argv[1], encoding="utf-8"))
before = json.load(open(sys.argv[2], encoding="utf-8"))
def paths(items):
    return {item["id"]: item.get("localFilePath") for item in items}
if paths(after) != paths(before):
    raise SystemExit(f"失败后 queue 路径被改写了: {paths(after)} != {paths(before)}")
if [item["id"] for item in after] != [item["id"] for item in before]:
    raise SystemExit("失败后 queue 条目被改写了")
PY
test ! -f "$support/media-folder-move.inprogress"
if defaults read Replay MediaFolderPath >/dev/null 2>&1; then
    echo "失败后不得写入 MediaFolderPath" >&2
    exit 1
fi
echo "fail rollback source_kept dest_conflict_untouched marker=cleared pref_unchanged"

echo "media_folder_launch_move=passed work=$work"
