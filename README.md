# BREY Web Friend Edition

A SEPARATE browser edition of BREY, based on the supplied V1.2.7 file.

It is intended for friends using iPhone/iPad Safari or other browsers.

## Local test

```bash
flutter clean
flutter pub get
flutter run -d chrome
```

## Build

```bash
flutter build web --release
```

The finished website is in `build/web`.

## Publish a playable link with GitHub Pages

1. Create a NEW GitHub repository, e.g. `brey-web-friend`.
2. Upload all files in this folder.
3. Push to the `main` branch.
4. GitHub: Settings -> Pages -> Source: GitHub Actions.
5. Wait for the workflow to finish.
6. GitHub will show the public URL.
7. Send that URL to your iPhone friend; they can play in Safari.

The included workflow automatically sets the correct repository base path.

IMPORTANT: This is completely separate from the main BREY V1.23 Android development.
