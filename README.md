# Ai Manuver Camera

Ai Manuver Camera adalah aplikasi pemindai iPhone berbasis SwiftUI. Aplikasi mengambil gambar melalui kamera atau Photos, mengenali teks dan kode menggunakan framework Vision, lalu menyimpan hasil secara lokal dengan SwiftData.

Dokumen ini menjelaskan implementasi yang tersedia saat ini, konfigurasi proyek, alur build, dan batasan yang perlu diketahui sebelum aplikasi digunakan atau didistribusikan.

## Ringkasan

- Platform minimum: iOS 18.0
- Perangkat sasaran: iPhone
- Bahasa implementasi: Swift
- Antarmuka: SwiftUI
- Pemrosesan gambar: Vision dan VisionKit
- Penyimpanan lokal: SwiftData
- Integrasi jaringan AI: URLSession dengan protokol `AIProvider`
- Identitas aplikasi: Ai Manuver Camera
- Skema Xcode: `Ai Manuver Camera`

Tidak ada API key AI yang disimpan di source code. Analisis AI hanya dapat digunakan setelah endpoint HTTPS milik pengguna dikonfigurasi.

## Fitur yang tersedia

### Pemindaian dan OCR

- Mengambil gambar menggunakan kamera perangkat atau memilih gambar dari Photos.
- Memindai dokumen menggunakan `VNDocumentCameraViewController` dari VisionKit.
- Mengenali teks pada gambar dengan `VNRecognizeTextRequest` pada tingkat akurasi tinggi.
- Memeriksa bahasa OCR yang tersedia di perangkat. Untuk Bahasa Indonesia, aplikasi memakai model OCR yang tersedia; jika model Indonesia tidak tersedia, aplikasi menggunakan fallback pengenalan aksara Latin dan mematikan koreksi bahasa.
- Mendeteksi barcode dan QR pada gambar menggunakan `VNDetectBarcodesRequest`.
- Menyimpan hasil teks atau kode, jenis scan, waktu pembuatan, dan thumbnail.

### Riwayat dan privasi

- Menyimpan hasil scan secara lokal dengan SwiftData.
- Mencari berdasarkan judul, isi, atau jenis scan.
- Mengedit judul dan teks, menyalin, membagikan, menghapus, dan mengekspor data riwayat sebagai JSON.
- Menampilkan konfirmasi sebelum menghapus seluruh riwayat.
- Memproses OCR dan deteksi kode di perangkat. Foto tidak diunggah secara otomatis.
- Meminta persetujuan sebelum mengirim teks hasil scan ke endpoint AI yang dikonfigurasi.

### Pengaturan

- Bahasa antarmuka: System, English, atau Bahasa Indonesia.
- Skema warna: System, Light, atau Dark.
- Auto Scan: analisis langsung setelah pengambilan gambar atau menampilkan pratinjau untuk ditinjau terlebih dahulu.
- Haptic Feedback dan Save Scan Automatically.
- Bahasa pengenalan OCR: otomatis, Indonesia, atau Inggris.
- Konfigurasi penyedia AI, nama model, dan endpoint HTTPS.
- Ekspor dan penghapusan riwayat.

## Fitur yang belum tersedia

Bagian berikut belum memiliki implementasi lengkap. Beberapa di antaranya sudah memiliki tombol navigasi, tetapi belum menghasilkan fungsi yang dijanjikan:

- Kamera live khusus berbasis AVFoundation dengan preview, flash, pergantian kamera, dan deteksi otomatis real-time.
- Deteksi objek dan bounding box; tombol Identify Object belum menjalankan model deteksi.
- Alur khusus QR/barcode yang langsung mengelompokkan seluruh tipe payload seperti URL, Wi-Fi, kontak, email, dan nomor telepon.
- Alur dokumen multi-halaman, ekspor PDF, dan berbagi PDF. VisionKit dapat menangkap beberapa halaman, tetapi implementasi sekarang memproses halaman pertama.
- Fitur AI selain Summarize dan Explain. Fitur ini memerlukan backend milik pengguna.
- WidgetKit dan App Intents.

## Struktur proyek

```text
Ai Manuver Camera.xcodeproj/
Ai Camera Scanner/
├── AiManuverCameraApp.swift       # Entry point dan kontainer SwiftData
├── ContentView.swift              # Tab utama, dashboard, riwayat, dan alur scan
├── Models.swift                   # ScanType dan model SwiftData ScanItem
├── Services.swift                 # OCR, deteksi kode, dan abstraksi AI
├── SupportingViews.swift          # Detail, Settings, kamera, dan VisionKit bridge
├── id.lproj/
│   └── Localizable.strings        # Teks antarmuka Bahasa Indonesia
└── Assets.xcassets/
    └── AppIcon.appiconset/        # Ikon aplikasi
```

Proyek menggunakan Xcode filesystem-synchronized group, sehingga file Swift dan aset di direktori aplikasi otomatis menjadi bagian target.

## Persyaratan pengembangan

- macOS dengan Xcode yang mendukung target iOS 18.
- iOS Simulator untuk menjalankan build simulator.
- iPhone dan konfigurasi Apple Development signing untuk memasang build langsung dari Xcode.
- Koneksi jaringan hanya diperlukan untuk fitur AI melalui endpoint yang disediakan sendiri.

Tidak ada dependency Swift Package Manager eksternal.

## Build untuk iOS Simulator

Jalankan dari root repository:

```sh
xcodebuild \
  -project "Ai Manuver Camera.xcodeproj" \
  -scheme "Ai Manuver Camera" \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -derivedDataPath /tmp/ai-manuver-camera-simulator \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Bundle simulator akan dibuat di:

```text
/tmp/ai-manuver-camera-simulator/Build/Products/Debug-iphonesimulator/Ai Manuver Camera.app
```

## Build untuk perangkat iPhone

Build perangkat tanpa code signing:

```sh
xcodebuild \
  -project "Ai Manuver Camera.xcodeproj" \
  -scheme "Ai Manuver Camera" \
  -sdk iphoneos \
  -configuration Debug \
  -derivedDataPath /tmp/ai-manuver-camera-device \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Bundle perangkat akan dibuat di:

```text
/tmp/ai-manuver-camera-device/Build/Products/Debug-iphoneos/Ai Manuver Camera.app
```

Build tanpa signing ditujukan untuk diproses oleh alat sideload yang menandatangani aplikasi saat instalasi. iOS tidak memasang bundle `.app` unsigned secara langsung. Untuk distribusi atau pemasangan melalui Xcode, atur Team dan provisioning profile di **Signing & Capabilities**.

Untuk mengemas IPA, struktur ZIP harus menempatkan `Payload` di direktori teratas arsip:

```text
manuscan.ipa
└── Payload/
    └── manuscan.app/
```

## Konfigurasi AI

`ProxyAIProvider` mengirim permintaan `POST` JSON ke endpoint yang diatur pengguna. Endpoint harus menggunakan HTTPS dan menerima bentuk data berikut:

```json
{
  "prompt": "Summarize this document.",
  "text": "Extracted text from the scan",
  "model": "model-name"
}
```

Respons yang diharapkan:

```json
{
  "text": "Summary returned by the server"
}
```

Simpan kredensial penyedia AI di backend. Jangan menaruh secret provider dalam aplikasi iOS. Aplikasi mengirim teks hasil OCR, bukan gambar, dan hanya setelah pengguna memilih aksi AI serta mengonfirmasi pengiriman.

## Izin dan pemrosesan data

Aplikasi meminta izin kamera dan akses Photos melalui deskripsi penggunaan pada Info.plist yang dihasilkan Xcode. Pemindaian dokumen memakai layar VisionKit milik Apple. Hasil scan disimpan pada database SwiftData lokal aplikasi.

Jika AI diaktifkan, teks scan yang dipilih dikirim ke endpoint HTTPS konfigurasi. Pengelola endpoint bertanggung jawab atas pemrosesan, retensi, autentikasi, dan kebijakan privasi server tersebut.

## Pemecahan masalah

### Bahasa Indonesia tidak tersedia pada OCR

Vision menyediakan daftar bahasa OCR yang bergantung pada versi OS dan revision model. Aplikasi memeriksa daftar runtime tersebut dan menggunakan fallback aksara Latin bila model Indonesia tidak tersedia. Fallback ini mengenali bentuk karakter, tetapi tidak menerapkan koreksi ejaan Bahasa Indonesia.

### Sideloading gagal

Gunakan build `iphoneos`, bukan build `iphonesimulator`. Alat sideload harus menerima IPA dengan `Payload/` di root arsip dan menandatangani aplikasi menggunakan kredensial pengembang. Error autentikasi Anisette berasal dari alat sideload dan proses login Apple ID, bukan dari OCR atau kode aplikasi.

## Lisensi dan distribusi

Repository ini belum menyertakan file lisensi. Sebelum distribusi publik, tambahkan lisensi, kebijakan privasi yang berlaku untuk produk, serta endpoint backend AI yang dikelola dan diamankan oleh pemilik aplikasi.
