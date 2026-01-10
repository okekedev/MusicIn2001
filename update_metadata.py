#!/usr/bin/env python3
"""
Script to update track metadata in the Mixor app library
"""
import json
import plistlib
import os
from pathlib import Path

# Path to the app's preferences
prefs_path = os.path.expanduser("~/Library/Preferences/com.okekedev.mixor.plist")

# Track metadata mappings based on filename patterns
METADATA_MAP = {
    "Lecrae - Always Knew": {"artist": "Lecrae", "album": "All Things Work Together"},
    "King Chav-Born Ready": {"artist": "King Chav", "album": "The Golden Lining"},
    "Steven Malcolm": {"artist": "Steven Malcolm", "album": "Tree"},
    "SUMMERTIME": {"artist": "Steven Malcolm", "album": "Tree"},
    "Braille - IV": {"artist": "Braille", "album": "The IV Edition"},
    "Fugees - The Mask": {"artist": "Fugees", "album": "The Score"},
    "Mission ft. V. Rose - Thank the Lord": {"artist": "Mission", "album": "Thank the Lord (Single)"},
    "Japhia Life": {"artist": "Japhia Life", "album": "Westside Pharmacy"},
    "Small World": {"artist": "Japhia Life", "album": "Westside Pharmacy"},
    "Ready or Not": {"artist": "Lecrae & 1K Phew", "album": "No Church in a While"},
    "Sleight of Hand": {"artist": "King Chav", "album": "The Leftovers"},
    "Live at the Rio": {"artist": "King Chav & Rab G", "album": "Pen 'N Teller"},
    "Gucci Mane - 4 Lifers": {"artist": "Gucci Mane", "album": "Instrumental"},
    "Metro Boomin - Metro Spider": {"artist": "Metro Boomin", "album": "Instrumental"},
    "Travis Scott - 4X4": {"artist": "Travis Scott", "album": "Instrumental"},
    "Youngs Teflon - Stay Dangerous": {"artist": "Youngs Teflon", "album": "Instrumental"},
    "Too Young": {"artist": "Unknown", "album": "Instrumental"},
    "Russ Type Beat": {"artist": "Type Beat", "album": "Instrumental"},
    "ISAIAH RASHAD": {"artist": "Type Beat", "album": "Instrumental"},
    "Fresh (feat. Ebonique)": {"artist": "Fresh", "album": "Single"},
    "Enough 2 Bury Me": {"artist": "Unknown", "album": "Single"},
    "HELP!": {"artist": "Unknown", "album": "Single"},
    "Iron Sharpens Iron": {"artist": "Unknown", "album": "Single"},
    "KNOCKED OUT": {"artist": "Unknown", "album": "Single"},
    "Letter to Lindsay": {"artist": "Unknown", "album": "Single"},
    "Multiple Choice": {"artist": "King Chav", "album": "Single"},
    "Not the Same": {"artist": "Unknown", "album": "Single"},
    "Parable Rhymes": {"artist": "Unknown", "album": "Single"},
    "Poker Face": {"artist": "Lecrae & 1K Phew", "album": "No Church in a While"},
    "Posted Notes": {"artist": "Unknown", "album": "Single"},
    "Shadowboxing": {"artist": "Unknown", "album": "Single"},
    "Sit Here": {"artist": "Unknown", "album": "Single"},
    "Summer Back": {"artist": "Unknown", "album": "Single"},
    "We Will Remember": {"artist": "Braille", "album": "The IV Edition"},
}

def find_metadata(filename):
    """Find matching metadata for a filename"""
    for pattern, meta in METADATA_MAP.items():
        if pattern.lower() in filename.lower():
            return meta
    return None

def update_library():
    # Read plist
    try:
        with open(prefs_path, 'rb') as f:
            prefs = plistlib.load(f)
    except FileNotFoundError:
        print(f"Preferences file not found: {prefs_path}")
        return

    # Get library data
    library_key = "savedLibrary"
    if library_key not in prefs:
        print("No library found in preferences")
        return

    library_data = prefs[library_key]
    library = json.loads(library_data)

    updated_count = 0
    for track in library:
        title = track.get("title", "")
        file_url = track.get("fileURL", "")
        filename = os.path.basename(file_url) if file_url else title

        meta = find_metadata(filename) or find_metadata(title)
        if meta:
            old_artist = track.get("artist", "Unknown Artist")
            old_album = track.get("album", "Unknown Album")

            if old_artist == "Unknown Artist" or old_album == "Unknown Album" or old_album == "Unknown" or old_album == "YouTube":
                track["artist"] = meta["artist"]
                track["album"] = meta["album"]
                print(f"Updated: {title}")
                print(f"  Artist: {old_artist} -> {meta['artist']}")
                print(f"  Album: {old_album} -> {meta['album']}")
                updated_count += 1

    # Save back
    prefs[library_key] = json.dumps(library).encode('utf-8') if isinstance(library_data, bytes) else json.dumps(library)

    with open(prefs_path, 'wb') as f:
        plistlib.dump(prefs, f)

    print(f"\nUpdated {updated_count} tracks")

if __name__ == "__main__":
    update_library()
