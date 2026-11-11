from pathlib import Path


def write_text(file, content, encoding="utf-8"):
    path = Path(file)
    data = content.encode(encoding)
    if not path.exists() or path.read_bytes() != data:
        path.write_bytes(data)
    return len(content)
