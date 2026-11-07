# Recovery schema

`schema.ckdb` is the verified development export for `iCloud.com.arjunakankipati.sweatkit`, team `TDBAHN96B3`, on 5 November 2026. It preserves the existing Users type and adds RecoveryRecord with envelope Bytes and original Asset. RecoveryRecord has no public-database grants; the app uses the private database only.

Development validation and import succeeded, followed by a fresh export confirming the fields. No activity records were uploaded. Production initially contained only Users. The user subsequently promoted the schema through CloudKit Console. A fresh production export on 5 November confirmed RecoveryRecord with envelope BYTES and original ASSET (`/tmp/sweatkit-wave2-cloud-production-deployed.ckdb`). Production schema deployment is verified.

Next, exercise signed-device copy, two-device convergence, offline deletion and wiped-device restore with an approved test dataset. A schema export does not certify transport or recovery behavior.

Apple reference: https://developer.apple.com/documentation/cloudkit/integrating-a-text-based-schema-into-your-workflow
