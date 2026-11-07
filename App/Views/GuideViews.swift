import SwiftUI

struct KeyboardGuideView: View {
    var body: some View {
        List {
            Section {
                StepRow(number: 1, text: "Ayarlar › Genel › Klavye › Klavyeler › Yeni Klavye Ekle… › \"Sesli Yaz\"")
                StepRow(number: 2, text: "Listede \"Sesli Yaz\"a dokun ve \"Tam Erişime İzin Ver\"i aç. (Klavyenin uygulamayla konuşabilmesi için gerekli. Klavye hiçbir tuş vuruşunu kaydetmez veya göndermez.)")
                StepRow(number: 3, text: "Herhangi bir uygulamada klavyedeki 🌐 tuşuna basılı tut ve \"Sesli Yaz\"ı seç.")
                Button("Ayarlar'ı aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } header: {
                Text("Kurulum (bir kere)")
            }

            Section {
                StepRow(number: 1, text: "Sesli Yaz klavyesindeki 🎤'a bas.")
                StepRow(number: 2, text: "Oturum kapalıysa Sesli Yaz bir anlığına açılır ve mikrofonu hazırlar. Sol üstteki ◀ ile geri dön.")
                StepRow(number: 3, text: "🎤'a bas, konuş, tekrar bas. Metin imlecin olduğu yere yazılır.")
            } header: {
                Text("Kullanım")
            } footer: {
                Text("Apple, klavyelerin mikrofonu doğrudan kullanmasına izin vermiyor. Bu yüzden kaydı arka planda Sesli Yaz uygulaması yapar. Oturum açık kaldıkça uygulamaya tekrar gitmen gerekmez.")
            }
        }
        .navigationTitle("Klavye")
    }
}

struct BackTapGuideView: View {
    var body: some View {
        List {
            Section {
                StepRow(number: 1, text: "Kestirmeler uygulamasında + ile yeni kestirme oluştur. Adı: \"Sesli Yaz\".")
                StepRow(number: 2, text: "\"Ses Kaydet\" eylemini ekle. Ayrıntılarında: Ses Kalitesi \"Normal\", Kaydı Başlat \"Hemen\", Bitir \"Dokununca\".")
                StepRow(number: 3, text: "\"Sesli Yaz › Sesi Yazıya Çevir\" eylemini ekle. Ses: \"Kaydedilen Ses\" olmalı, \"Panoya kopyala\" açık kalsın.")
                StepRow(number: 4, text: "(İsteğe bağlı) \"Bildirim Göster\" ekle ve metne \"Yazıya Çevrilen Metin\"i koy, böylece ne yazıldığını görürsün.")
                Button("Kestirmeler'i aç") {
                    if let url = URL(string: "shortcuts://") { UIApplication.shared.open(url) }
                }
            } header: {
                Text("1. Kestirmeyi oluştur")
            }

            Section {
                StepRow(number: 1, text: "Ayarlar › Erişilebilirlik › Dokunma › Arkaya Dokun")
                StepRow(number: 2, text: "\"İki Kez Dokun\" › listeden \"Sesli Yaz\" kestirmesini seç.")
            } header: {
                Text("2. Arkaya dokunmaya bağla")
            }

            Section {
                StepRow(number: 1, text: "İstediğin uygulamada telefonun arkasına iki kez dokun.")
                StepRow(number: 2, text: "Konuş, bitince ekrandaki kayıt düğmesine dokun.")
                StepRow(number: 3, text: "Metin panoya kopyalanır. Yazı alanına uzun basıp \"Yapıştır\"a dokun.")
            } header: {
                Text("Kullanım")
            } footer: {
                Text("iOS, uygulamaların başka bir uygulamanın yazı alanına doğrudan yazmasına izin vermez. Bu yüzden arkaya dokunma yolunda metin panoya kopyalanır. Doğrudan yazdırmak istersen Sesli Yaz klavyesini kullan.\n\nAlternatif: \"Ses Kaydet\" yerine tek bir \"Sesli Yaz › Dikte Et\" eylemi de seçebilirsin. Bu eylem uygulamayı açıp hemen dinlemeye başlar.")
            }
        }
        .navigationTitle("Arkaya Dokunma")
    }
}
