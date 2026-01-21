Generating image screenshots from saved terminal outputs

This folder should contain terminal output text files (created by the helper `capture_outputs.sh`) and the generated PNG images.

Prerequisites
- ImageMagick (`convert`) installed. On Ubuntu/Debian:

```bash
sudo apt update
sudo apt install imagemagick
```

Quick steps
1. Run the output capture helper (saves text files into `screenshots/`):

```bash
chmod +x ./capture_outputs.sh generate_images.sh
./capture_outputs.sh
```

2. Convert the `.txt` files to PNG images:

```bash
./generate_images.sh
```

This will create PNGs alongside the `.txt` files, e.g.:
- `screenshots/create_ec2_dryrun.png`
- `screenshots/create_s3_bucket_dryrun.png`
- `screenshots/create_security_group_dryrun.png`
- `screenshots/cleanup_resources_dryrun.png`

3. (Optional) Manually take OS screenshots instead of generating images from text — use Win+Shift+S (Windows), Cmd+Shift+4 (macOS), or your Linux screenshot tool.

Embedding images in `README.md`

Add image references in your main `README.md` like:

```markdown
### Screenshots

![Create EC2 (dry-run)](screenshots/create_ec2_dryrun.png)

![Create S3 (dry-run)](screenshots/create_s3_bucket_dryrun.png)

![Create SG (dry-run)](screenshots/create_security_group_dryrun.png)

![Cleanup (dry-run)](screenshots/cleanup_resources_dryrun.png)
```

Notes
- The generated PNGs are plain text renderings; for prettier screenshots, take OS screenshots of the terminal windows.
- If text is very long, resize or crop the image as needed using an image editor or `convert` options.
