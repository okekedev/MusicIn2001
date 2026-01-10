#!/usr/bin/env python3
"""
Mixor CLI - Entry point for Swift subprocess calls
Outputs JSON for Swift to parse progress and results
"""

import os
import sys
import json
import argparse
import shutil
from pathlib import Path

# Ensure proper encoding
os.environ['PYTHONIOENCODING'] = 'utf-8'


def emit_progress(progress: float, status: str, step: str):
    """Emit progress update as JSON line for Swift to parse"""
    update = {"progress": progress, "status": status, "step": step}
    print(json.dumps(update), flush=True)


def emit_result(success: bool, instrumental_path: str = None, vocals_path: str = None,
                title: str = None, duration: float = None, error: str = None):
    """Emit final result as JSON"""
    result = {
        "success": success,
        "instrumentalPath": instrumental_path,
        "vocalsPath": vocals_path,
        "title": title,
        "duration": duration,
        "error": error
    }
    print(json.dumps(result), flush=True)


def get_audio_duration(file_path: Path) -> float:
    """Get audio duration using ffprobe"""
    try:
        import subprocess
        result = subprocess.run([
            'ffprobe', '-v', 'error', '-show_entries', 'format=duration',
            '-of', 'default=noprint_wrappers=1:nokey=1', str(file_path)
        ], capture_output=True, text=True)
        return float(result.stdout.strip())
    except:
        return None


def process_youtube(url: str, output_dir: str):
    """Process YouTube URL: download and separate vocals"""
    # Debug: print Python info
    print(f"DEBUG: Python executable: {sys.executable}", file=sys.stderr)
    print(f"DEBUG: Python version: {sys.version}", file=sys.stderr)

    import torch

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    temp_dir = output_path / "temp"
    temp_dir.mkdir(exist_ok=True)

    instrumentals_dir = output_path / "Instrumentals"
    instrumentals_dir.mkdir(exist_ok=True)

    acapellas_dir = output_path / "Acapellas"
    acapellas_dir.mkdir(exist_ok=True)

    # Determine device
    if torch.cuda.is_available():
        device = "cuda"
    elif torch.backends.mps.is_available():
        device = "mps"
    else:
        device = "cpu"

    try:
        # Step 1: Download
        emit_progress(0.1, "Downloading audio...", "download")

        import yt_dlp

        # Find ffmpeg
        ffmpeg_location = None
        if sys.platform == 'darwin':
            for path in ['/opt/homebrew/bin', '/usr/local/bin']:
                if os.path.exists(os.path.join(path, 'ffmpeg')):
                    ffmpeg_location = path
                    break

        # Match original working yt-dlp options exactly
        ydl_opts = {
            'format': 'bestaudio/best',
            'postprocessors': [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '192',
            }],
            'outtmpl': str(temp_dir / '%(title)s.%(ext)s'),
            'quiet': False,
            'no_warnings': False,
            'extractaudio': True,
            'noplaylist': True,
            'ffmpeg_location': '/opt/homebrew/bin',
        }

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            title = info.get('title', 'Unknown')
            duration = info.get('duration')

            # Clean filename
            safe_title = "".join(c for c in title if c.isalnum() or c in (' ', '-', '_')).rstrip()

            # Find downloaded file
            audio_file = None
            for file in temp_dir.glob("*.mp3"):
                if file.exists():
                    audio_file = file
                    break

            if not audio_file:
                emit_result(False, error="Download failed - audio file not found")
                return

        emit_progress(0.3, "Processing with Demucs...", "demucs")

        # Step 2: Run Demucs
        import subprocess

        model = "htdemucs_ft"
        cmd = [
            sys.executable, "-m", "demucs",
            "--two-stems=vocals",
            "-n", model,
            "-o", str(output_path),
            "--device", device,
            "--mp3",
            str(audio_file)
        ]

        env = os.environ.copy()
        env['PYTHONIOENCODING'] = 'utf-8'

        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', env=env)

        if result.returncode != 0:
            emit_result(False, error=f"Demucs error: {result.stderr}")
            return

        emit_progress(0.9, "Finalizing...", "finalize")

        # Step 3: Move output files
        output_name = audio_file.stem
        model_dir = output_path / model / output_name
        instrumental_file = model_dir / "no_vocals.mp3"
        vocals_file = model_dir / "vocals.mp3"

        if not instrumental_file.exists():
            emit_result(False, error="Processing failed - output file not found")
            return

        # Move to final locations
        final_instrumental = instrumentals_dir / f"{output_name}.mp3"
        final_acapella = acapellas_dir / f"{output_name}.mp3"

        shutil.move(str(instrumental_file), str(final_instrumental))
        if vocals_file.exists():
            shutil.move(str(vocals_file), str(final_acapella))

        # Cleanup
        shutil.rmtree(model_dir.parent, ignore_errors=True)
        audio_file.unlink(missing_ok=True)

        emit_progress(1.0, "Complete!", "done")
        emit_result(
            True,
            instrumental_path=str(final_instrumental),
            vocals_path=str(final_acapella),
            title=safe_title,
            duration=duration
        )

    except Exception as e:
        emit_result(False, error=str(e))


def process_local_file(file_path: str, output_dir: str):
    """Process local audio file: separate vocals"""
    import torch

    input_file = Path(file_path)
    if not input_file.exists():
        emit_result(False, error=f"File not found: {file_path}")
        return

    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    instrumentals_dir = output_path / "Instrumentals"
    instrumentals_dir.mkdir(exist_ok=True)

    acapellas_dir = output_path / "Acapellas"
    acapellas_dir.mkdir(exist_ok=True)

    # Determine device
    if torch.cuda.is_available():
        device = "cuda"
    elif torch.backends.mps.is_available():
        device = "mps"
    else:
        device = "cpu"

    try:
        emit_progress(0.1, "Preparing audio...", "prepare")

        title = input_file.stem
        duration = get_audio_duration(input_file)

        emit_progress(0.2, "Processing with Demucs...", "demucs")

        # Run Demucs
        import subprocess

        model = "htdemucs_ft"
        cmd = [
            sys.executable, "-m", "demucs",
            "--two-stems=vocals",
            "-n", model,
            "-o", str(output_path),
            "--device", device,
            "--mp3",
            str(input_file)
        ]

        env = os.environ.copy()
        env['PYTHONIOENCODING'] = 'utf-8'

        result = subprocess.run(cmd, capture_output=True, text=True, encoding='utf-8', errors='replace', env=env)

        if result.returncode != 0:
            emit_result(False, error=f"Demucs error: {result.stderr}")
            return

        emit_progress(0.9, "Finalizing...", "finalize")

        # Move output files
        output_name = input_file.stem
        model_dir = output_path / model / output_name
        instrumental_file = model_dir / "no_vocals.mp3"
        vocals_file = model_dir / "vocals.mp3"

        if not instrumental_file.exists():
            emit_result(False, error="Processing failed - output file not found")
            return

        # Move to final locations
        final_instrumental = instrumentals_dir / f"{output_name}.mp3"
        final_acapella = acapellas_dir / f"{output_name}.mp3"

        shutil.move(str(instrumental_file), str(final_instrumental))
        if vocals_file.exists():
            shutil.move(str(vocals_file), str(final_acapella))

        # Cleanup
        shutil.rmtree(model_dir.parent, ignore_errors=True)

        emit_progress(1.0, "Complete!", "done")
        emit_result(
            True,
            instrumental_path=str(final_instrumental),
            vocals_path=str(final_acapella),
            title=title,
            duration=duration
        )

    except Exception as e:
        emit_result(False, error=str(e))


def main():
    parser = argparse.ArgumentParser(description="Mixor CLI for Swift subprocess")
    parser.add_argument("command", choices=["extract_url", "extract_file"])
    parser.add_argument("--url", help="Video URL")
    parser.add_argument("--file", help="Local file path")
    parser.add_argument("--output", default=os.path.expanduser("~/Library/Application Support/Mixor/Output"))

    args = parser.parse_args()

    if args.command == "extract_url":
        if not args.url:
            emit_result(False, error="URL is required")
            return
        process_youtube(args.url, args.output)

    elif args.command == "extract_file":
        if not args.file:
            emit_result(False, error="File path is required")
            return
        process_local_file(args.file, args.output)


if __name__ == "__main__":
    main()
