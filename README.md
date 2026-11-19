# think — iOS

Минималистичное приложение для сохранения идей голосом и текстом.

## Возможности

- Живой световой шар на главном экране (SwiftUI Canvas).
- Запись идей голосом через Speech и AVFoundation, текстовый редактор.
- Локальное хранение идей, редактирование, поиск.
- Бесплатные QR-коды с текстом, система звёзд и 7-дневный цикл возвращения к идеям.
- Сборка неподписанного `Think.ipa` в GitHub Actions для установки через Sideloadly.

## Как получить IPA

Откройте [Actions](https://github.com/qwekurasa/think-ios/actions), выберите **Think iOS IPA** и скачайте артефакт **Think-IPA-Sideloadly** после успешной сборки. В архиве находится `Think.ipa`. Sideloadly подпишет его при установке.

## Исходники и сборка

- `Think/Sources/` — приложение на SwiftUI.
- `make_project.py` — генератор Xcode-проекта и иконки на macOS runner.
- `Think.xcodeproj/xcshareddata/xcschemes/Think.xcscheme` — общая схема для сборки.
- `.github/workflows/think-ipa.yml` — GitHub Actions.

Ориентир: iOS 17+. Bundle ID: `com.think.ideas.personal` (сохранён для обновлений приложения).

Проект перенесён из ветки `think-ios-build` репозитория `qwekurasa/tempt`; исходная ветка сохранена без изменений.
