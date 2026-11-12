# AES Team App

Android app for Aishwarya Engineering Services: about 150 workers and drivers, the office, and 15–16 substations. Built with Flutter and Firebase.

## What it does

| For | Feature |
| --- | --- |
| Everyone | Mobile OTP login (only numbers added by admin) |
| Everyone | Selfie + GPS attendance: office = In / Out, substation = Site time |
| Everyone | Leave: planned, medical (doctor certificate), emergency (certificate within 3 days) |
| Everyone | Salary advance request, carry-forward request, site expense (payment) request with bill photo |
| Everyone | Bank details with cheque/passbook proof, locked after verification |
| Everyone | Own payslips, advance balance, assigned jobs with photo updates |
| Drivers | Daily start/end odometer km with photos |
| Admin | Live Today board, all approvals (red after 24 h), payroll, jobs, quotes and invoices (GST, PDF), reports, sites, staff |

**Salary** = Days paid × Per-day rate + Km × Per-km rate − PF+ESI (₹2,100 default) − Advance recovery ± Adjustment

- Days paid = full days (In + Out) + approved leave (planned, or medical/emergency with certificate)
- Advance is recovered from the next salary unless a carry-forward is approved
- Example: 26 × ₹800 = ₹20,800 − ₹2,100 − ₹3,000 advance = **₹15,700**

## Who sees what

| Role | Sees | Can do |
| --- | --- | --- |
| Owner | Everything | Everything; add managers; reopen approved payslips |
| Manager | Everything | Approve others' requests (never their own), payroll, jobs, billing, exports |
| Worker / Driver | Only their own records | Punch, raise requests, upload documents |

Enforced on the server by `firestore.rules` and `storage.rules`, not just hidden in the app.

## Folder map

| Path | Contents |
| --- | --- |
| `lib/main.dart` | App start, login routing |
| `lib/company.dart` | Company name, address, phone, **GSTIN** for PDFs (fill in GSTIN) |
| `lib/models/` | Data: staff, sites, attendance, leave, requests, bank, vehicle log, payslip, job, bill |
| `lib/services/` | Firebase reads/writes, GPS/geofence, payroll calculation, PDF |
| `lib/screens/` | Worker screens: Attendance, Requests, Pay, Vehicle, Me |
| `lib/screens/admin/` | Today, Approvals, Payroll, Jobs, Billing, Reports, Sites, Staff |
| `firestore.rules`, `storage.rules` | Privacy and permission rules |
| `firestore.indexes.json` | Database indexes |

## Setup (Flutter developer, about 2–3 hours)

1. Install Flutter 3.24+ and Android Studio.
2. In this folder, create the Android project files and fetch packages:
   ```
   flutter create --platforms=android --org com.aishwaryaengg .
   flutter pub get
   ```
3. Create a Firebase project at console.firebase.google.com and switch it to the **Blaze** (pay-as-you-go) plan. Storage and phone OTP need it. At 150 users, expect a small monthly bill; set a budget alert. Then enable:
   - Authentication → **Phone**
   - **Firestore**, region `asia-south1` (Mumbai)
   - **Storage**, same region
4. Connect the app (this replaces `lib/firebase_options.dart`):
   ```
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
5. Add the app's SHA-1 and SHA-256 in Firebase → Project settings → Android app (needed for OTP):
   ```
   cd android && ./gradlew signingReport
   ```
   Also enable the **Play Integrity API** in Google Cloud for the project.
6. `android/app/src/main/AndroidManifest.xml`, inside `<manifest>` (above `<application>`):
   ```xml
   <uses-permission android:name="android.permission.INTERNET"/>
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
   <uses-permission android:name="android.permission.CAMERA"/>
   <queries>
     <intent>
       <action android:name="android.intent.action.VIEW"/>
       <data android:scheme="https"/>
     </intent>
   </queries>
   ```
   In `android/app/build.gradle`: `minSdk 23`.
7. Deploy rules and indexes:
   ```
   npm i -g firebase-tools
   firebase login
   firebase init firestore storage     # keep the existing rules/index files
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```
   When asked, allow Storage rules to read Firestore (admins need it to view photos).
8. Create the **owner** account once, by hand, in Firestore:
   collection `users` → document id `+91XXXXXXXXXX` (owner's mobile) → fields
   `name` (string), `role` = `owner`, `perDayRate` = 0, `pfEsi` = 0, `active` = true.
9. Fill `gstin` in `lib/company.dart`.
10. Test on a phone: `flutter run`. Release: `flutter build apk --release` (share the APK on WhatsApp) or `flutter build appbundle` for the Play Store.

If a screen shows "requires an index", open the link in the error once; Firebase creates it.

## First use (owner)

1. **Admin → Sites**: stand at the office → *Add site → Office → Use my current location* (100 m). Repeat at each substation (200 m).
2. **Admin → Staff**: add each person: mobile, name, role, per-day rate, PF+ESI. Drivers also get per-km rate and vehicle number. Add managers (owner only).
3. Staff install the app, log in with OTP, then add bank details on the **Me** tab. Verify them in **Approvals → Bank**.

## Monthly payroll (1st–2nd of each month)

1. **Approvals**: clear pending leave, certificates, advances and carry-forwards for last month.
2. **Payroll** → pick last month → **Calculate**.
3. Check people with *incomplete* days (missing Out punch). Tap a person to adjust days, km, advance recovery, or add an adjustment with a note.
4. **Approve all**. Workers now see their payslip.
5. **Bank transfer sheet** → share to accounts or upload to net banking bulk transfer. People without verified bank details are listed in red.

## Attendance logic

| Where | Already today | Recorded as |
| --- | --- | --- |
| Office | nothing | In time |
| Substation | anything | Site time (site tagged) |
| Office | In done | Out time (asks to confirm) |
| Outside all sites | — | Blocked |

Also blocked: GPS off, accuracy worse than ±100 m, fake-GPS app. Selfie is camera-only. Each punch stores photo, time, GPS and accuracy, and cannot be edited by the worker.

## Status

Not yet compiled: this code was written without a Flutter SDK. Expect a round of small fixes on the first `flutter pub get` / `flutter run` (package version bumps, analyzer warnings). Test all three roles (owner, manager, worker/driver) before giving it to 150 people. Start with a pilot of 10–15 staff for one month alongside the current attendance register.

Still open (from the spec): driver pay basis (km only, or per-day + km), Tamil language, and the full staff rate sheet.
