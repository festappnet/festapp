# TrinaGrid Migration Tool

This tool helps you migrate your code from PlutoGrid to TrinaGrid by automatically replacing references in your codebase.

## Usage

Run the migration tool from your project root:

```bash
# Using the Flutter pub run command (recommended)
flutter pub run trina_grid --migrate-from-pluto-grid

# For a dry run to see what would be changed
flutter pub run trina_grid --migrate-from-pluto-grid --dry-run
```

### Options

- `--dry-run`: Show changes without applying them
- `--dir`, `-d`: Specify the directory to migrate (defaults to current directory)
- `--verbose`, `-v`: Show detailed output
- `--scan-all`: Scan all directories, including build and platform-specific directories
- `--help`, `-h`: Show help message

### Examples

```bash
# Dry run to see what would be changed
flutter pub run trina_grid --migrate-from-pluto-grid --dry-run

# Migrate a specific directory
flutter pub run trina_grid --migrate-from-pluto-grid --dir=lib/screens

# Show detailed output and scan all directories
flutter pub run trina_grid --migrate-from-pluto-grid --verbose --scan-all
```
