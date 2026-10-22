# Easy CamSorter

A macOS app that imports photos and videos from a camera card and sorts them into folders by capture date.

[![Tests](https://github.com/istvikoo/easy-camsorter/actions/workflows/tests.yml/badge.svg)](https://github.com/istvikoo/easy-camsorter/actions/workflows/tests.yml)
[![Latest release](https://img.shields.io/github/v/release/istvikoo/easy-camsorter)](https://github.com/istvikoo/easy-camsorter/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**[⬇️ Download / Завантажити](https://github.com/istvikoo/easy-camsorter/releases/latest)** · **[English](#english)** · **[Українська](#українська)**

---

## English

### Features

- **Import from a camera card.** Insert a card into the card reader and the app detects it. Files are copied to `~/Pictures` and sorted by date.
- **Verified copies.** Each file is written under a temporary name, read back from disk and compared with the original by SHA-256. Only then does it get its real name.
- **Safe card cleanup.** After the import, the app offers to delete the originals from the card. It deletes only files whose copies were verified. Right before deleting, it checks again that the copy is in place and the original hasn't changed. Then you can eject the card from the app.
- **No duplicates.** Importing the same card again doesn't create `_1` copies. Files that are already imported are only verified.
- **Organize a folder in place.** Drop any folder into the window to sort it.
- **Preview first.** Nothing changes until you confirm.
- **Selective import with thumbnails.** Untick files or whole days you don't need (a RAW's `.xmp` follows it). Double-click a file to open it in Quick Look. Unticked files aren't copied and are never deleted from the card.
- **UA / EN interface.** Switch the language with the toggle in the bottom-right corner.
- **Automatic updates** via [Sparkle](https://sparkle-project.org): the app checks GitHub Releases once a day and installs new versions in one click (menu **Easy CamSorter → Check for Updates…**).

### Where files go

| Type | Extensions | Destination |
|---|---|---|
| Photos | jpg, jpeg, heic, png… | `<date>/` |
| RAW | cr3, cr2, nef, arw, dng, raf… | `<date>/raw/` |
| XMP | xmp | next to its RAW file, with the same name |
| Videos | mp4, mov, mts, avi, mkv… | `<date>/video/` |
| Gyroflow | gyroflow | next to the video with the same name (searched across the whole folder) |
| Video thumbnails | thm (Canon, GoPro) | next to the video |
| Video metadata | xml (Sony `C0001M01.XML`), srt (DJI telemetry) | next to the video; only if the matching video is found |
| Proxies | lrv (GoPro `GL…`, DJI) | `<date>/video/proxy/` |
| NiYien gyro logs | `*_mix.bin` | `<date>/video/gyro/` (date from the file name) |
| PSD | psd, psb | `<date>/PSD/` |
| Canon service files | ctg, cpf | Trash (when importing, they stay on the card) |
| Anything else | | stays where it is |

Video companion files follow their video: same folder, and the same `_1` suffix if the video had to be renamed.

The capture date comes from photo and video metadata. exiftool isn't needed. If a file has no capture date, its modification date is used, and the file is marked in the list.

You choose the date-folder format in the window:

- **Ukrainian:** `15 травня 2024`, `2024-05-15 (15 травня)`, `2024 / 15 травня 2024`
- **English:** `15 May 2024`, `2024-05-15 (15 May)`, `2024 / 15 May 2024`

### Download and install

1. Download `EasyCamSorter-…-macOS.zip` from [Releases](https://github.com/istvikoo/easy-camsorter/releases/latest) and unzip it.
2. Move **Easy CamSorter.app** to **Applications**.
3. On first launch, macOS blocks the app because it isn't notarized by Apple. To allow it, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. Or run in Terminal:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Easy CamSorter.app"
   ```

You need macOS 14 or later, on Apple Silicon or Intel.

### Build

You only need the Command Line Tools. Xcode isn't required.

```bash
./build.sh        # builds "build/Easy CamSorter.app"
swift test        # runs the tests
```

Building a version for Apple Silicon and Intel: `UNIVERSAL=1 ./build.sh`.

### Releases

Push a version tag and GitHub Actions will run the tests, build the universal app and publish it to Releases:

```bash
git tag -a v1.3.0 -m "- what's new…" && git push origin v1.3.0
```

The tag message becomes the "What's new" text on the release page and in the update window.
Updates are signed with an EdDSA key (Sparkle). The private key must be stored as the repository secret `SPARKLE_PRIVATE_KEY`; the public key is `SUPublicEDKey` in `Resources/Info.plist`.

---

## Українська

### Завантаження і встановлення

1. Завантажте `EasyCamSorter-…-macOS.zip` з [Releases](https://github.com/istvikoo/easy-camsorter/releases/latest) і розпакуйте.
2. Перенесіть **Easy CamSorter.app** у **Програми**.
3. Під час першого запуску macOS заблокує застосунок, бо він не нотаризований Apple. Щоб дозволити, відкрийте **Системні параметри → Приватність і безпека**, прокрутіть униз і натисніть **Усе одно відкрити**. Або виконайте в Терміналі:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Easy CamSorter.app"
   ```

Потрібна macOS 14 або новіша, на Apple Silicon або Intel.

### Можливості

- **Імпорт з картки камери.** Вставте картку в картрідер, і програма її побачить. Файли копіюються в «Зображення» (`~/Pictures`) і розкладаються за датами.
- **Перевірка кожної копії.** Файл пишеться під тимчасовою назвою, потім перечитується з диска і звіряється з оригіналом за SHA-256. Лише після цього він отримує справжню назву.
- **Безпечне очищення картки.** Після імпорту програма пропонує видалити оригінали з картки. Видаляються тільки файли з перевіреною копією. Безпосередньо перед видаленням програма ще раз перевіряє, що копія на місці, а оригінал не змінився. Потім картку можна витягнути прямо з програми.
- **Без дублікатів.** Повторний імпорт тієї самої картки не створює копій `_1`, а лише звіряє вже імпортовані файли.
- **Упорядкування папки на місці.** Перетягніть у вікно будь-яку папку, щоб розсортувати її.
- **Спершу перегляд.** Нічого не змінюється, доки ви не підтвердите.
- **Вибірковий імпорт з мініатюрами.** Зніміть галочки з непотрібних файлів чи цілих днів (`.xmp` іде разом зі своїм RAW). Подвійний клік відкриває файл у Quick Look. Невибрані файли не копіюються й ніколи не видаляються з картки.
- **Інтерфейс UA / EN.** Мову перемикає кнопка праворуч унизу.
- **Автооновлення** через [Sparkle](https://sparkle-project.org): раз на день програма перевіряє GitHub Releases і встановлює нову версію одним натисканням (меню **Easy CamSorter → Перевірити оновлення…**).

### Куди потрапляють файли

| Тип | Розширення | Куди |
|---|---|---|
| Фото | jpg, jpeg, heic, png… | `<дата>/` |
| RAW | cr3, cr2, nef, arw, dng, raf… | `<дата>/raw/` |
| XMP | xmp | поруч зі своїм RAW, з такою ж назвою |
| Відео | mp4, mov, mts, avi, mkv… | `<дата>/video/` |
| Gyroflow | gyroflow | до відео з такою ж назвою (шукається по всій папці) |
| Мініатюри відео | thm (Canon, GoPro) | поруч з відео |
| Метадані відео | xml (Sony `C0001M01.XML`), srt (телеметрія DJI) | поруч з відео; лише якщо знайдено відповідне відео |
| Проксі | lrv (GoPro `GL…`, DJI) | `<дата>/video/proxy/` |
| Гіро-логи NiYien | `*_mix.bin` | `<дата>/video/gyro/` (дата з назви файлу) |
| PSD | psd, psb | `<дата>/PSD/` |
| Службові файли Canon | ctg, cpf | у Кошик (під час імпорту лишаються на картці) |
| Інше | | лишається на місці |

Супровідні файли відео йдуть за своїм відео: у ту саму папку і з тим самим суфіксом `_1`, якщо відео довелося перейменувати.

Дата береться з метаданих фото й відео. Якщо дати зйомки немає, береться дата зміни файлу, і такий файл позначається в списку.

Формат назв папок з датами вибирається у вікні, українською або англійською.

### Збірка

Потрібні лише Command Line Tools, Xcode не потрібен.

```bash
./build.sh        # збирає "build/Easy CamSorter.app"
swift test        # запускає тести
```

---

## Project structure

- `Sources/SorterCore` — the logic, with no UI:
  - `Planner` builds the plan;
  - `Executor` sorts a folder in place;
  - `Importer` copies with verification and deletes from the card.
- `Sources/EasyCamSorter` — the SwiftUI interface (`ThumbnailStore` makes Quick Look thumbnails).
- `Tests/SorterCoreTests` — tests for sorting, import and deletion.
- `tools/make-icon.swift` — draws the icon `Resources/AppIcon.icns`.

The UI doesn't use `@State`, because its macro ships only with Xcode.

## License · Ліцензія

[MIT](LICENSE) — free to use, modify and share, as long as the copyright notice is kept.
Вільно користуйтеся, змінюйте й поширюйте, зберігаючи згадку про автора.
