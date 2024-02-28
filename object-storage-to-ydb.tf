# Infrastructure for the Yandex Cloud Object Storage, Managed Service for YDB, and Data Transfer
#
# RU: https://cloud.yandex.ru/docs/data-transfer/tutorials/object-storage-to-ydb
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/object-storage-to-ydb
#
# Specify the following settings:
locals {

  folder_id   = "" # Set your cloud folder ID, same as for provider
  bucket_name = "" # Set a unique bucket name

  # Specify these settings ONLY AFTER the cluster is created. Then run the "terraform apply" command again.
  # You should set up a source endpoint for the Object Storage bucket using the GUI to obtain endpoint's ID
  source_endpoint_id = "" # Set the source endpoint ID
  transfer_enabled   = 0  # Set to 1 to enable the transfer

  # The following settings are predefined. Change them only if necessary.
  sa-name              = "s3-ydb-account"  # Name of the service account
  ydb_name             = "ydb1"            # Name of the YDB
  target_endpoint_name = "ydb-target"      # Name of the target endpoint for the YDB
  transfer_name        = "s3-ydb-transfer" # Name of the transfer from the Object Storage bucket to the Managed Service for YDB
}

# Create a service account
resource "yandex_iam_service_account" "example-sa" {
  folder_id = local.folder_id
  name      = local.sa-name
}

# Infrastructure for the Object Storage bucket

# Create a static key for the service account
resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  service_account_id = yandex_iam_service_account.example-sa.id
}

# Grant a role to the service account. The role allows to perform any operations with buckets and objects.
resource "yandex_resourcemanager_folder_iam_binding" "s3-editor" {
  folder_id = local.folder_id
  role      = "storage.editor"

  members = [
    "serviceAccount:${yandex_iam_service_account.example-sa.id}",
  ]
}

# Create a Lockbox secret
resource "yandex_lockbox_secret" "sa-key-secret" {
  name        = "sa-key-secret"
  description = "Contains a static key pair to create an endpoint"
  folder_id   = local.folder_id
}

# Create a version of Lockbox secret with the static key pair
resource "yandex_lockbox_secret_version" "first_version" {
  secret_id = yandex_lockbox_secret.sa-key-secret.id
  entries {
    key        = "access_key"
    text_value = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  }
  entries {
    key        = "secret_key"
    text_value = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
  }
}

# Create the Yandex Object Storage bucket
resource "yandex_storage_bucket" "example-bucket" {
  bucket     = local.bucket_name
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
}

# Infrastructure for the Managed Service for YDB

# Create the Yandex Managed Service for YDB
resource "yandex_ydb_database_serverless" "ydb" {
  name        = local.ydb_name
  location_id = "ru-central1"
}

# Grant a role to the service account. The role allows to perform any operations with database.
resource "yandex_ydb_database_iam_binding" "ydb-editor" {
  database_id = yandex_ydb_database_serverless.ydb.id
  role        = "ydb.editor"

  members = [
    "serviceAccount:${yandex_iam_service_account.example-sa.id}",
  ]
}

# Data Transfer infrastructure

resource "yandex_datatransfer_endpoint" "ydb-target" {
  description = "Target endpoint for YDB"
  name        = local.target_endpoint_name
  settings {
    ydb_target {
      database           = yandex_ydb_database_serverless.ydb.database_path
      cleanup_policy     = "YDB_CLEANUP_POLICY_DROP"
      service_account_id = yandex_iam_service_account.example-sa.id
    }
  }
}

resource "yandex_datatransfer_transfer" "objstorage-ydb-transfer" {
  count       = local.transfer_enabled
  description = "Transfer from the Object Storage bucket to the Managed Service for YDB"
  name        = local.transfer_name
  source_id   = local.source_endpoint_id
  target_id   = yandex_datatransfer_endpoint.ydb-target.id
  type        = "SNAPSHOT_AND_INCREMENT" # Copy all data from the source and start replication
}
