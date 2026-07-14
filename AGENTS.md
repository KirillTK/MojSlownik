# Mój Słownik — архитектура

Личное iOS-приложение для изучения польского языка с русского. Без бэкенда,
без авторизации, без синхронизации — все данные локально на устройстве.
Устанавливается на личный iPhone через Xcode (бесплатный Apple ID, переподпись
раз в 7 дней) — см. README.md.

## Стек

- **SwiftUI** — весь UI, deployment target iOS 17.0.
- **SwiftData** — локальное хранилище, одна модель `Word`.
- **XcodeGen** — `MojSlownik.xcodeproj` генерируется из `project.yml`
  (`xcodegen generate`); сам `.xcodeproj` в git не хранится.
- Русский язык интерфейса; названия файлов и кода — английские.

## Структура

```
project.yml                  # конфиг XcodeGen (bundle id, Info.plist, camera permission)
MojSlownik/
├── MojSlownikApp.swift      # @main, ModelContainer(for: Word.self)
├── Models/
│   └── Word.swift           # @Model: russian, polish, sourceLanguageCode, createdAt
│                            #   + SRS-поля: easeFactor, intervalDays, repetitions, dueDate
├── Services/
│   ├── LanguageDetector.swift    # enum AppLanguage (ru/pl) + детекция по алфавиту:
│   │                             #   есть кириллица → русский, иначе польский
│   ├── TranslationService.swift  # протокол TranslationService + фасад Translator:
│   │                             #   iOS 18+ → Apple Translation (офлайн, с 4-с таймаутом),
│   │                             #   иначе/при ошибке → MyMemory
│   ├── MyMemoryTranslator.swift  # GET api.mymemory.translated.net/get (бесплатно, без ключа;
│   │                             #   email в параметре de поднимает лимит до 50k симв/день)
│   ├── AppleTranslator.swift     # мост к Translation framework: TranslationSession выдаётся
│   │                             #   только через .translationTask, поэтому AppleTranslationModel
│   │                             #   хранит continuation, а AppleTranslationHost (модификатор на
│   │                             #   RootTabView) исполняет перевод. На iOS 17 — no-op.
│   ├── SpeechService.swift       # AVSpeechSynthesizer, голоса pl-PL / ru-RU, офлайн
│   └── SRSEngine.swift           # упрощённый SM-2: оценки again/hard/good/easy двигают
│                                 #   easeFactor, intervalDays и dueDate
├── Views/
│   ├── RootTabView.swift         # TabView: Словарь + Тренировка; здесь висит AppleTranslationHost
│   ├── WordListView.swift        # @Query-список, поиск, swipe-delete, кнопки «+» и камера;
│   │                             #   сканер отдаёт текст → sheet AddWordView с prefill
│   ├── AddWordView.swift         # ввод слова, автоопределение языка, автоперевод с debounce
│   │                             #   600 мс, редактируемый перевод; чипы слов из скана
│   ├── ScannerView.swift         # ScannerScreen (разрешение камеры, недоступность в симуляторе)
│   │                             #   + DataScannerViewController (VisionKit): живое распознавание,
│   │                             #   тап по тексту → onPick(transcript)
│   ├── TrainingView.swift        # статистика + вход в карточки и викторину
│   ├── FlashcardsView.swift      # SRS-сессия: due-слова (или 10 случайных, если due нет),
│   │                             #   тап = перевернуть, 4 кнопки оценки → SRSEngine
│   ├── QuizView.swift            # 10 вопросов, 4 варианта, случайное направление, счёт
│   └── Components/
│       └── PronounceButton.swift # кнопка озвучки
└── Theme/
    └── Theme.swift               # палитра (индиго-акцент #5B5FEF, тёплые нейтральные),
                                  #   динамические цвета light/dark, модификатор .cardStyle()
```

## Ключевые решения и ограничения

- **Перевод**: основной путь на iOS 17 — MyMemory (нужен интернет при добавлении
  слова). Перевод всегда редактируемый перед сохранением — качество MyMemory
  нестабильно для редких слов. После обновления устройства до iOS 18 Translator
  автоматически предпочитает офлайн-перевод Apple (нужно один раз скачать
  языковые пакеты ru/pl; в симуляторе Apple Translation не работает).
- **Направление**: определяется автоматически — `LanguageDetector` смотрит на
  алфавит. Слово всегда сохраняется парой (russian, polish).
- **OCR**: Vision может не поддерживать польский на iOS 17 — тогда распознавание
  идёт latin-моделью и диакритика (ą, ę, ł…) может теряться; текст правится в
  AddWordView перед сохранением. Сканер работает только на реальном устройстве.
- **SwiftData-предикаты**: due-слова фильтруются в памяти (`words.filter(\.isDue)`),
  а не в `#Predicate` — для личного словаря объёмы крошечные.

## Сборка

```sh
xcodegen generate                        # после изменения project.yml или добавления файлов
xcodebuild -project MojSlownik.xcodeproj -scheme MojSlownik \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Если активный тулчейн — CommandLineTools, добавить `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Проверка изменений

1. Сборка в симуляторе без warnings.
2. Добавить «привет» → появляется польский перевод; добавить «dziękuję» → русский.
3. Прогнать сессию флешкарточек (оценки меняют dueDate) и викторину.
4. Сканер — только на устройстве: навести на польский текст, тапнуть слово,
   проверить чипы выбора слова в AddWordView.
