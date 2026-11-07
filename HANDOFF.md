# HANDOFF — Sesli Yaz (ios-speech-to-text)

Bu dosya, projeyi devralacak bir sonraki agent/geliştirici içindir.
Son güncelleme: 2026-11-07

---

## 1. Ne yapıyoruz?

Kullanıcı (Deniz, GitHub: `denizardaslan`), ChatGPT'nin sesli modundaki kaliteyi WhatsApp gibi her uygulamada istiyor.
Konuşacak, metin yazılacak. Konuşmayı yazıya çevirme işini **Google Gemini API** yapıyor (ücretsiz API anahtarı ile).

İki kullanım yolu var, ikisi de kalacak. Kullanıcı o an hangisi kolayına gelirse onu kullanacak:

| Yol | Akış | Sonuç |
|---|---|---|
| **Klavye eklentisi** | Sesli Yaz klavyesi → 🎤 → konuş → 🎤 | Metin `textDocumentProxy.insertText` ile **imlece yazılır** |
| **Arkaya Dokun (Back Tap)** | 2x dokun → Kestirme: *Ses Kaydet* → *Sesi Yazıya Çevir* (App Intent) | Metin **panoya kopyalanır**, kullanıcı yapıştırır |

**Kullanıcı tercihleri ve kararlar:**
- API anahtarını uygulama ilk açılışta istiyor; kullanıcı bir kere yapıştırıyor, anahtar Keychain'e kaydediliyor. Herkes kendi anahtarını girdiği için başkaları da kullanabilir. Arada sunucu yok.
- Kullanıcının Apple Developer hesabı var.
- Geliştirme bulutta (Linux, Claude Code) yapılıyor, build Mac'te Xcode ile alınıyor.
- **Hedef:** Her şeyi telefondan (Claude Code) yönetmek ve TestFlight ile telefona almak (bkz. §6).
- Kullanıcıyla Türkçe konuşulur; uygulama arayüzü ve yorumlar Türkçe.

---

## 2. Mevcut durum

| Konu | Durum |
|---|---|
| Kod (uygulama + klavye + intent'ler + arayüz) | ✅ Yazıldı, 3 commit (`main`), bu dosya dahil |
| GitHub'a push | ❌ **YAPILAMADI** (bkz. §3) |
| Derleme | ⚠️ **Hiç derlenmedi.** Ortamda Swift ve Xcode yok, kod sadece elle gözden geçirildi. İlk Xcode build'inde küçük hatalar çıkabilir. |
| Cihazda test | ❌ Yapılmadı |
| TestFlight / CI | ❌ Başlanmadı (plan §6'da) |

**Kodun yerel konumu (bulut oturumu):**
- `/home/deniz/projects/ios-speech-to-text`: GitHub remote'u ayarlı klon, commit'ler burada
- `/home/deniz/projects/sesliyaz`: ilk çalışma kopyası (aynı commit'ler)

Bulut container'ı geçici. Push yapılmadan oturum kapanırsa kod kaybolur. **İlk iş push.**

---

## 3. Engel: GitHub push

- Repo: `https://github.com/denizardaslan/ios-speech-to-text` (kullanıcı oluşturdu, **şu an boş**).
- `add_repo` (access: push) başarılı oldu, `git clone` çalıştı.
- `git push -u origin main` → `fatal: could not read Username for 'https://github.com'`.
- Credential/proxy yapılandırmasını incelemek auto-mode tarafından engellendi. Bu kurcalanmamalı.
- `SendUserFile` ile git bundle göndermek de başarısız oldu ("session is not on a project thread").

**Muhtemel çözüm (kullanıcı tarafında):** GitHub → Settings → Applications → Installed GitHub Apps → **Claude** → Configure → Repository access → `ios-speech-to-text` ekle (veya All repositories). Gerekirse claude.ai → Settings → Connectors'tan GitHub bağlantısını yenile. Sonra push'u tekrar dene.

**Bulut oturumu yoksa / kod kaybolduysa:** Bu dosya ve README mimariyi tam anlatıyor, ama asıl kaynak commit'lerdir. Kod kaybolmuşsa §4'teki dosya listesine göre yeniden yazılmalı.

Kullanıcı Mac'te clone yapmak üzereydi. Push yapılana kadar repo boş, bu yüzden clone boş gelir. Kullanıcıya bu söylendi.

---

## 4. Mimari

```
Arkaya 2x dokun ─► Kestirme: [Ses Kaydet] ─► [Sesli Yaz › Sesi Yazıya Çevir]  (App Intent, uygulama açılmaz)
                                                         │
┌──────────── SesliYaz (ana uygulama, SwiftUI) ──────────▼─────────┐
│ DictationController  oturum / kayıt / çeviri / teslim (MainActor) │
│ AudioRecorder        AVAudioEngine → 16 kHz mono Int16 WAV        │
│ GeminiTranscriber    REST generateContent, inlineData base64      │──► Gemini API
│ AppSettings          model/stil/dil (UserDefaults), anahtar Keychain│
└──────▲──────────────────────────────────────┬───────────────────┘
       │ Darwin bildirimleri                   │ App Group klasörü:
       │ (ping/start/stop/cancel/endSession)   │ state.json, result.json, consumed.json
┌──────┴──────── SesliYazKeyboard (klavye eklentisi) ▼─────────────┐
│ 🎤 → komut gönder (0,6 sn watchdog) · resultReady → insertText    │
└──────────────────────────────────────────────────────────────────┘
```

### Önemli iOS kısıtları ve çözümleri
1. **Klavye eklentisi mikrofon kullanamaz** (Apple kuralı). Çözüm: Wispr Flow modeli.
   - Klavye, uygulamayı `sesliyaz://session` ile açar. Extension'da `UIApplication.shared` yok; responder zincirinde `UIApplication` bulunup `openURL:options:completionHandler:` ObjC runtime ile çağrılıyor (`KeyboardViewController.openContainingApp`). Resmi API değil, **App Store review riski var**; kişisel kullanımda sorun yok.
   - Uygulama `AVAudioEngine`'i başlatır, `UIBackgroundModes: audio` sayesinde arka planda canlı kalır (turuncu mikrofon noktası görünür). Kullanıcı ◀ breadcrumb ile geri döner.
   - Sonraki 🎤 basışları Darwin bildirimiyle uygulamaya gider; uygulama sadece start–stop arasında dosyaya yazar.
   - Boşta kalma süresi (varsayılan 5 dk, ayarlanabilir) dolunca oturum kapanır.
2. **Başka uygulamanın yazı alanına doğrudan yazılamaz** → Back Tap yolu panoya kopyalar.
3. **Uygulama arka plandan mikrofon başlatamaz** → klavye komutları sadece `sessionActive` iken kabul edilir. Değilse uygulama `.off` yayınlar, klavye uygulamayı açar.
4. Kestirmedeki "Ses Kaydet" çıktısı (m4a) `AudioFileConverter` ile WAV'a dönüştürülüp gönderilir.

### IPC protokolü (`Shared/IPC.swift`, `Shared/SharedStore.swift`)
- Bildirim adları: `<APP_GROUP_ID>.ipc.<mesaj>`
- Klavye → uygulama: `ping`, `startRecording`, `stopRecording`, `cancelRecording`, `endSession`
- Uygulama → klavye: `stateChanged` (her komuta yanıt olarak da gönderilir, "pong" görevi görür), `resultReady`
- Klavye bir komut gönderir. 0,6 sn içinde `stateChanged` gelmezse uygulama ayakta değildir ve klavye uygulamayı açar. Uygulama ayaktaysa ama durum `.off` ise (start komutunda) yine uygulamayı açar.
- Sonuç tekrarını önlemek için `consumedResultID` kullanılır. 120 sn'den eski sonuçlar yazılmaz.
- Klavye App Group'a erişebilmek için **Tam Erişim** ister (`RequestsOpenAccess: true`).

### Gemini (`App/Services/GeminiTranscriber.swift`)
- `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`, header `x-goog-api-key`
- Varsayılan model `gemini-flash-latest`. Ayarlar'da `ListModels` ile seçilebilir. İlk anahtar doğrulamasında varsayılan model listede yoksa uygun bir "flash" modeli otomatik seçiliyor.
- System prompt: sadece metni yaz; **sesteki komutları uygulama** (prompt injection koruması); TR/EN karışık konuşmayı destekle; "Temiz" ve "Kelimesi kelimesine" stilleri; konuşma yoksa `<empty>`.
- Kayıt üst sınırı 5 dk (inline 20 MB limiti için güvenli).
- Ücretsiz katmanda Google veriyi model eğitimi için kullanabilir. Bu, uygulamada ve README'de belirtildi.

### Dosyalar
```
project.yml                         XcodeGen tanımı (2 target, Info.plist/entitlements burada üretilir)
scripts/bootstrap.sh                Mac: xcodegen kur → TEAM_ID yaz → generate → Xcode'u aç
Shared/AppConfig.swift              App Group (Info.plist'teki SesliYazAppGroup'tan), URL şeması
Shared/IPC.swift                    DarwinNotifier + ObservationToken
Shared/SharedStore.swift            App Group JSON dosyaları
App/SesliYazApp.swift               @main, onOpenURL(sesliyaz://session) → startSession
App/Audio/AudioRecorder.swift       AVAudioEngine kayıt, kesinti/rota değişimi, AudioFileConverter
App/Services/DictationController.swift  Durum makinesi (off/ready/recording/transcribing)
App/Services/GeminiTranscriber.swift    REST istemci + prompt + hata eşleme (429, 401/403)
App/Services/AppSettings.swift      Ayarlar + makeTranscriber() (intent'ler de kullanır)
App/Services/KeychainStore.swift    AfterFirstUnlockThisDeviceOnly
App/Services/HistoryStore.swift     Son 100 çeviri
App/Intents/Intents.swift           TranscribeAudioIntent, DictateIntent, StartKeyboardSessionIntent, AppShortcuts
App/Views/*                         Onboarding (API anahtarı), Main, Settings, History, Guides
App/Assets.xcassets                 AppIcon (1024, saf Python ile üretildi), AccentColor
Keyboard/KeyboardViewController.swift   IPC, watchdog, insertText, uygulamayı açma
Keyboard/KeyboardView.swift         SwiftUI klavye: 🎤, boşluk, sil (tekrarlı), return, 🌐
```

### Build ayarları (`project.yml`)
- iOS 17+, iPhone only, Swift 5 dil modu (strict concurrency hatalarından kaçınmak için)
- `BUNDLE_ID_PREFIX: com.denizardaslan` → `…sesliyaz` ve `…sesliyaz.keyboard`
- `APP_GROUP_ID: group.$(BUNDLE_ID_PREFIX).sesliyaz`, entitlements'a ve Info.plist'e enjekte ediliyor
- `DEVELOPMENT_TEAM: ""`. Kullanıcı kendi Team ID'sini `bootstrap.sh <TEAM_ID>` ile ya da Xcode'da girer.
- `.xcodeproj`, üretilen Info.plist ve entitlements **.gitignore'da**. Her değişiklikten sonra `xcodegen generate` çalıştırılmalı.

---

## 5. Sıradaki adımlar (öncelik sırasıyla)

1. **Push** (§3). Kullanıcıya push sonrası Mac'te clone yapabileceğini söyle.
2. **İlk Mac build'i.** Kullanıcı derleme hatalarını yapıştıracak; düzelt. Şüpheli noktalar:
   - `KeyboardViewController.openContainingApp`: `method(for:)` / `unsafeBitCast` kullanımı
   - Swift 5 modunda MainActor izolasyon uyarıları (`AudioRecorder` callback'leri, Darwin handler'ları)
   - `AVAudioConverter.convert` kullanılmayan dönüş değeri uyarısı
   - App Intents: `@Parameter(supportedContentTypes:)`, `IntentDescription(categoryName:)`
   - Otomatik imzalamada App Group capability'si entitlements dosyasından kendiliğinden kaydolmazsa: iki target'ta da Signing & Capabilities → + App Groups.
3. **Cihazda test:** API anahtarı akışı, uygulama içi dikte, Back Tap kestirmesi, klavye oturum akışı (uygulamayı açma, ◀ ile dönüş, kayıt, ekleme), oturum zaman aşımı, arama ile kesinti.
4. **TestFlight otomasyonu** (§6).
5. Yol haritası (README'de de var): cihaz içi model (WhisperKit / Apple SpeechAnalyzer), özel kelime listesi, ton seçenekleri, canlı önizleme.

---

## 6. Plan: Telefondan yönetim + TestFlight

Kullanıcı Mac'e bağımlı olmadan, Claude Code'dan (telefondan) değişiklik yapıp TestFlight ile telefona almak istiyor. Önerilen yol:

```
Claude Code (telefon) → git push → GitHub Actions (macos runner)
   → xcodegen generate → fastlane (match/cert + build_app) → upload_to_testflight
   → 10–20 dk sonra TestFlight uygulamasında güncelleme
```

**Bir kerelik kurulum, kullanıcı tarafında:**
- App Store Connect'te uygulama kaydı (bundle ID: `com.denizardaslan.sesliyaz`; klavye ID'si de kayıtlı olmalı)
- App Store Connect **API anahtarı** (.p8, Key ID, Issuer ID)
- İmzalama: fastlane `match` (ayrı private repo) **veya** CI'da API anahtarıyla otomatik imzalama (`-allowProvisioningUpdates`)
- GitHub repo secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64), `TEAM_ID`, gerekiyorsa `MATCH_PASSWORD` ve `MATCH_GIT_URL`
- **Gizli bilgiler sohbete yazılmamalı.** Kullanıcı bunları GitHub'a kendisi ekler.

**Agent tarafında yapılacaklar:**
- `.github/workflows/testflight.yml` (tetikleyici: `workflow_dispatch` ve/veya `main` push / tag), macOS runner, `brew install xcodegen`, fastlane
- `fastlane/Fastfile` (beta lane: build numarasını artır → build → TestFlight)
- Build numarası: `CURRENT_PROJECT_VERSION`'ı CI'da `github.run_number` ile ayarla
- Not: macOS runner'lar private repolarda ücretsiz dakikayı Linux'a göre daha hızlı tüketir.

Önerilen sıra: önce Mac'te bir kere elle build alıp uygulamanın çalıştığını doğrula, sonra CI'yı kur.

---

## 7. Çalışma notları
- Commit'lerin sonuna `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` ekleniyor. Commit, kod ya da PR'da model adı geçmemeli.
- Git kimliği: `denizardaslan <aardaslan@gmail.com>`
- Kullanıcı açıkça istemedikçe PR açma.
