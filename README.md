# MyMember

Android Flutter app untuk pengelolaan member, event, QR card, dan presensi online dengan Supabase.

## First run

1. Install APK dan pastikan perangkat online.
2. Masukkan email aktif dan password minimal 8 karakter untuk membuat admin pertama.
3. Verifikasi email dari Supabase, lalu login.
4. Buat tipe member tambahan bila perlu, kemudian mulai menambah/import member.

Setelah admin pertama dibuat, backend menolak signup akun baru. Semua tabel operasional memakai RLS admin-only. Foto tersimpan di bucket private dan hanya dibaca melalui signed URL.

## CSV member

Header yang didukung:

```csv
nama,nik,email,nohp,tipe,status
```

Nilai `tipe` harus sama dengan nama tipe member yang sudah ada. Status default adalah `active`.

## Quality checks

```powershell
flutter analyze
flutter test
supabase db lint --linked --level warning
flutter build apk --release
```

Migration cloud berada di `supabase/migrations`. Publishable key pada aplikasi memang public-by-design; keamanan data ditangani Auth dan Row Level Security. Service-role key tidak disimpan di aplikasi.
