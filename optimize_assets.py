import os
import sys
import json
import subprocess

def run_cmd(cmd):
    print("Running:", cmd)
    res = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if res.returncode != 0:
        print("Warning/Error:", res.stderr)
    return res.returncode == 0

def main():
    assets_dir = os.path.join("www", "assets")
    project_json_path = os.path.join(assets_dir, "project.json")
    
    if not os.path.exists(project_json_path):
        print(f"Error: {project_json_path} not found!")
        sys.exit(1)
        
    with open(project_json_path, "r", encoding="utf-8") as f:
        project = json.load(f)
        
    # 1. Create a tiny silent MP3 file (0.1s at 24000Hz)
    silent_mp3_bytes = (
        b'\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
        b'\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
        b'\xff\xfb\x90\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00'
    )
    
    # 2. Identify the 7 redundant 17MB cover tracks
    # These 7 fan covers take ~110MB on disk and ~1.2GB of decoded RAM!
    REDUNDANT_COVERS = [
        "Twenty4", "Dark", "Hydro", "PLAWERIAN", "Voylter", "Z3noX", "Jschlarpo"
    ]
    
    cover_asset_ids = set()
    for t in project.get("targets", []):
        for s in t.get("sounds", []):
            name = s.get("name", "")
            if any(c in name for c in REDUNDANT_COVERS):
                aid = s.get("assetId")
                cover_asset_ids.add(aid)
                # Set dummy sample count for silence
                s["sampleCount"] = 2400
                s["rate"] = 24000
                print(f"[OPTIMIZE] Muting redundant cover sound: {name} ({aid})")
                
    for aid in cover_asset_ids:
        fn = os.path.join(assets_dir, f"{aid}.mp3")
        if os.path.exists(fn):
            orig_sz = os.path.getsize(fn)
            with open(fn, "wb") as f_out:
                f_out.write(silent_mp3_bytes)
            print(f"Replaced {fn} ({orig_sz / 1024 / 1024:.2f} MB -> {os.path.getsize(fn)} bytes)")

    # 3. Optimize the 3 real game music tracks using ffmpeg if available
    # - Finality (fedd83ebed157ffe13db9aeda0230df9)
    # - Menu (25c7cd3056e5f694b2e474c2c33af370) - was also an invalid MP4 container
    # - Intro/Music (9fc40ebccd22a96e412c1483d4aac9a0)
    MUSIC_TRACKS = {
        "fedd83ebed157ffe13db9aeda0230df9": "Finality",
        "25c7cd3056e5f694b2e474c2c33af370": "Menu",
        "9fc40ebccd22a96e412c1483d4aac9a0": "Intro"
    }
    
    has_ffmpeg = run_cmd("ffmpeg -version")
    print(f"ffmpeg available: {has_ffmpeg}")
    
    if has_ffmpeg:
        for aid, title in MUSIC_TRACKS.items():
            in_file = os.path.join(assets_dir, f"{aid}.mp3")
            out_file = os.path.join(assets_dir, f"{aid}_opt.mp3")
            if os.path.exists(in_file):
                orig_sz = os.path.getsize(in_file)
                cmd = f'ffmpeg -y -i "{in_file}" -vn -ar 24000 -ac 1 -b:a 64k "{out_file}"'
                if run_cmd(cmd) and os.path.exists(out_file):
                    os.replace(out_file, in_file)
                    new_sz = os.path.getsize(in_file)
                    print(f"[OPTIMIZE] Compressed {title}: {orig_sz / 1024 / 1024:.2f} MB -> {new_sz / 1024 / 1024:.2f} MB")
                    
                    # Update project.json sample count
                    for t in project.get("targets", []):
                        for s in t.get("sounds", []):
                            if s.get("assetId") == aid:
                                # Estimate or compute new sampleCount at 24000 Hz
                                s["rate"] = 24000
                                if s.get("sampleCount"):
                                    s["sampleCount"] = int(s["sampleCount"] * (24000 / 48000))
    else:
        print("Note: ffmpeg not found in local environment, will run in GitHub Actions.")

    # Save updated project.json
    with open(project_json_path, "w", encoding="utf-8") as f:
        json.dump(project, f)
    print("Saved optimized project.json successfully.")

if __name__ == "__main__":
    main()
