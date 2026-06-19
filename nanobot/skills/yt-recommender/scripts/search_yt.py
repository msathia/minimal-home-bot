import json
import subprocess
import sys


def lookup_video_entries(topic_string):
    try:
        command = [
            "yt-dlp",
            "--get-title",
            "--get-id",
            "--flat-playlist",
            "--max-downloads",
            "3",
            f"ytsearch3:{topic_string}",
        ]
        terminal_dump = (
            subprocess.check_output(command, stderr=subprocess.DEVNULL)
            .decode()
            .split("\n")
        )

        compiled_data = []
        for ptr in range(0, len(terminal_dump) - 1, 2):
            if terminal_dump[ptr] and terminal_dump[ptr + 1]:
                compiled_data.append(
                    {
                        "title": terminal_dump[ptr],
                        "url": f"https://youtu.be/{terminal_dump[ptr + 1]}",
                    }
                )
        return json.dumps(compiled_data)
    except Exception as error_context:
        return json.dumps({"error": str(error_context)})


if __name__ == "__main__":
    search_term = sys.argv[1] if len(sys.argv) > 1 else "OpenAI development updates"
    print(lookup_video_entries(search_term))
