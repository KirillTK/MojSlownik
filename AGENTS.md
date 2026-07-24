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
│   ├── TranslationService.swift  # протокол TranslationService + фасад Translator, цепочка:
│   │                             #   iOS 18+ Apple Translation (офлайн, 4-с таймаут) →
│   │                             #   Google gtx (веб) → MyMemory (веб, запасной)
│   ├── GoogleWebTranslator.swift # неофициальный translate.googleapis.com client=gtx:
│   │                             #   без ключа, лучшее качество; основной путь на iOS 17
│   ├── MyMemoryTranslator.swift  # api.mymemory.translated.net (без ключа; email в de
│   │                             #   поднимает лимит). Краудсорсные совпадения бывают мусорными,
│   │                             #   поэтому кандидаты валидируются по алфавиту целевого языка
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
│   │                             #   сканер отдаёт текст → экран результата сканирования
│   ├── AddWordView.swift         # ввод слова, автоопределение языка, автоперевод с debounce
│   │                             #   600 мс, редактируемый перевод
│   ├── ScannerView.swift         # ScannerScreen (разрешение камеры, недоступность в симуляторе)
│   │                             #   + DataScannerViewController (VisionKit): живое распознавание,
│   │                             #   тап по тексту → ScanResultView: перевод строки, кликабельные
│   │                             #   слова и облачки; выбранное слово открывает AddWordView
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

- **Перевод**: основной путь на iOS 17 — Google gtx (нужен интернет при добавлении
  слова); эндпоинт неофициальный, при поломке Translator сам падает на MyMemory.
  Перевод всегда редактируемый перед сохранением. После обновления устройства до iOS 18 Translator
  автоматически предпочитает офлайн-перевод Apple (нужно один раз скачать
  языковые пакеты ru/pl; в симуляторе Apple Translation не работает).
- **Направление**: определяется автоматически — `LanguageDetector` смотрит на
  алфавит. Слово всегда сохраняется парой (russian, polish).
- **OCR**: Vision может не поддерживать польский на iOS 17 — тогда распознавание
  идёт latin-моделью и диакритика (ą, ę, ł…) может теряться; после тапа по
  строке показываются её перевод и слова для выбора, а выбранное слово можно
  поправить в AddWordView перед сохранением. Сканер работает только на реальном
  устройстве.
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
4. Сканер — только на устройстве: навести на польскую или русскую фразу,
   тапнуть строку, проверить её перевод и выбрать слово как в тексте, так и
   через облачко; после закрытия AddWordView результат сканирования остаётся
   доступен для выбора других слов.
