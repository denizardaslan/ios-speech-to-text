# Sesli Yaz 🎙️

iPhone'da her uygulamada (WhatsApp, Mail, Notlar…) **konuşarak yazmak** için bir uygulama.
Konuşmayı Google **Gemini API** ile yazıya çevirir: noktalama ekler, "ıı, eee"leri temizler, anlamı değiştirmez.

İki kullanım yolu var, o an hangisi kolayına gelirse:

| Yol | Nasıl | Sonuç |
|---|---|---|
| **Klavye** | Sesli Yaz klavyesine geç → 🎤 → konuş → 🎤 | Metin **imlecin olduğu yere yazılır** |
| **Arkaya dokunma** | Telefonun arkasına 2 kez dokun → konuş → dokun | Metin **panoya kopyalanır** → yapıştır |

---

## Mac'te kurulum

Gerekenler: Xcode 16 veya üzeri, Apple Developer hesabı, iOS 17 veya üzeri bir iPhone.

```bash
git clone https://github.com/denizardaslan/ios-speech-to-text.git
cd ios-speech-to-text
./scripts/bootstrap.sh ABCDE12345     # kendi Team ID'n (Xcode › Settings › Accounts)
```

Betik [XcodeGen](https://github.com/yonaskolb/XcodeGen)'i kurar (`brew install xcodegen`), `project.yml`'den `SesliYaz.xcodeproj`'u üretir ve Xcode'da açar.
> `.xcodeproj` repoda tutulmuyor. `project.yml` veya dosya yapısı değişince `xcodegen generate` komutunu tekrar çalıştır.

Xcode'da:
1. Üstten şemayı **SesliYaz** ve hedefi kendi iPhone'un olarak seç, ▶︎ ile çalıştır.
2. İmzalama hatası alırsan iki target'ta da (*SesliYaz*, *SesliYazKeyboard*) **Signing & Capabilities › Team** alanını seç.
   App Group (`group.com.denizardaslan.sesliyaz`) otomatik imzalamayla kendiliğinden oluşturulur.
3. Bundle ID'yi değiştirmek istersen `project.yml` içindeki `BUNDLE_ID_PREFIX` alanını değiştir. App Group da ona göre değişir.

## Telefonda ilk kurulum

1. **API anahtarı:** Uygulamayı aç. [aistudio.google.com/apikey](https://aistudio.google.com/apikey) adresinden ücretsiz anahtar al, yapıştır, "Kaydet ve doğrula"ya bas. Bunu bir kere yapman yeterli.
2. **Klavye:** Ayarlar › Genel › Klavye › Klavyeler › Yeni Klavye Ekle › *Sesli Yaz* → üstüne dokun → **Tam Erişime İzin Ver**.
3. **Arkaya dokunma:**
   - Kestirmeler uygulamasında yeni bir kestirme oluştur:
     1. **Ses Kaydet** (Kaydı Başlat: *Hemen*, Bitir: *Dokununca*)
     2. **Sesli Yaz › Sesi Yazıya Çevir** (Ses: *Kaydedilen Ses*)
     3. *(isteğe bağlı)* **Bildirim Göster** → *Yazıya Çevrilen Metin*
   - Ayarlar › Erişilebilirlik › Dokunma › **Arkaya Dokun** › İki Kez Dokun › bu kestirme.

Bu adımlar uygulamanın içindeki **Kurulum** bölümünde de anlatılıyor.

---

## Mimari

```
┌────────────────────────────── iPhone ──────────────────────────────┐
│                                                                    │
│  Arkaya 2x dokun ─► Kestirme: [Ses Kaydet] ─► [Sesi Yazıya Çevir] ──┐│
│                                                (App Intent)        ││
│  ┌──────────────── SesliYaz (ana uygulama) ─────────────────┐      ││
│  │ DictationController  ← oturum, kayıt, teslim             │◄─────┘│
│  │ AudioRecorder        ← AVAudioEngine → 16 kHz mono WAV   │       │
│  │ GeminiTranscriber    ← REST: generateContent (+ prompt)  │──────►│── HTTPS ─► Gemini API
│  │ AppSettings/Keychain ← API anahtarı, model, stil         │       │
│  └──────────▲─────────────────────────────┬─────────────────┘       │
│   Darwin    │ start/stop/cancel/ping      │ state.json / result.json │
│ bildirimleri│                             ▼ (App Group klasörü)      │
│  ┌──────────┴─────── SesliYazKeyboard (klavye eklentisi) ──┐        │
│  │ 🎤 → komut gönder   ·   sonuç gelince insertText()       │        │
│  └──────────────────────────────────────────────────────────┘        │
└────────────────────────────────────────────────────────────────────┘
```

### Klavye neden kaydı kendisi yapmıyor?
Apple, klavye eklentilerinin mikrofonu kullanmasına **izin vermiyor**. Bu yüzden:

1. 🎤'a ilk basışında klavye `sesliyaz://session` adresiyle ana uygulamayı açar.
2. Uygulama mikrofonu açar (`UIBackgroundModes: audio`), böylece arka planda çalışmaya devam eder. Sen sol üstteki **◀** ile geri dönersin.
3. Bundan sonra 🎤 basışları Darwin bildirimiyle uygulamaya gider. Uygulama kaydeder, Gemini'ye yollar ve sonucu App Group klasörüne yazar. Klavye metni `textDocumentProxy.insertText` ile imlece yazar.
4. Oturum, ayarlardaki süre boyunca (varsayılan 5 dk) kullanılmazsa mikrofon kapanır.

Oturum açıkken ekranın üstündeki **turuncu nokta** mikrofonun açık olduğunu gösterir. Ses sadece 🎤 ile bitiş arasında dosyaya yazılır ve gönderilir; geri kalanı hiçbir yere kaydedilmez.

### Arkaya dokunma neden panoya kopyalıyor?
iOS, bir uygulamanın başka bir uygulamanın yazı alanına doğrudan yazmasına izin vermez. Doğrudan yazmayı sadece klavye yapabilir.

### Dosyalar

```
project.yml                       XcodeGen proje tanımı (target'lar, izinler, Info.plist)
Shared/                           Uygulama + klavye ortak kodu
  AppConfig.swift                 App Group, URL şeması
  IPC.swift                       Darwin bildirimleri (süreçler arası sinyal)
  SharedStore.swift               App Group'taki JSON durum/sonuç dosyaları
App/
  SesliYazApp.swift               Giriş noktası, sesliyaz://session yakalama
  Audio/AudioRecorder.swift       AVAudioEngine kaydı + dosya dönüştürücü
  Services/DictationController    Oturum/kayıt/çeviri durum makinesi
  Services/GeminiTranscriber      Gemini REST istemcisi + prompt
  Services/AppSettings, Keychain  Ayarlar ve API anahtarı
  Intents/Intents.swift           Kestirme eylemleri (App Intents)
  Views/                          SwiftUI ekranları
Keyboard/
  KeyboardViewController.swift    Klavye ↔ uygulama iletişimi, metin ekleme
  KeyboardView.swift              Klavye arayüzü (SwiftUI)
```

## Gizlilik
- API anahtarı sadece cihazdaki **Keychain**'de tutulur.
- Ses, **doğrudan** Google'a gider; arada sunucu yok.
- ⚠️ Gemini'nin **ücretsiz katmanında** Google, gönderilen içeriği ürünlerini geliştirmek için kullanabilir. Hassas içerik için ücretli katmanı (faturalandırma açık proje) düşünebilirsin.
- Klavye hiçbir tuş vuruşunu kaydetmez. "Tam Erişim" sadece uygulamayla haberleşmek için gerekli.

## Bilinen sınırlar / yol haritası
- [ ] Cihaz içi (çevrimdışı) model seçeneği (WhisperKit / Apple SpeechAnalyzer)
- [ ] Özel kelime listesi (isimler, terimler) → prompt'a eklenir
- [ ] Ton seçenekleri ("resmi e-posta", "kısa mesaj")
- [ ] Kayıt sırasında canlı ön izleme (streaming)
- Klavyenin uygulamayı açması için kullanılan yöntem (responder zinciri) Apple'ın resmi API'si değil. Kişisel kullanımda sorun yok, ama App Store incelemesinde sorun çıkarabilir.
