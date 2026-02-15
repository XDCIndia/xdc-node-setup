/*
Copyright 2024 XDC Network.
Licensed under the Apache License, Version 2.0.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// XDCBackupSpec defines the desired state of an XDC backup policy.
type XDCBackupSpec struct {
	// NodeRef references the XDCNode resource to back up.
	NodeRef string `json:"nodeRef"`

	// Schedule is a cron expression for backup timing.
	Schedule string `json:"schedule"`

	// RetentionDays is the number of days to retain backups.
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=365
	// +kubebuilder:default=30
	RetentionDays int32 `json:"retentionDays,omitempty"`

	// Destination configures where backups are stored.
	Destination BackupDestination `json:"destination"`

	// Compression enables gzip compression of backups.
	// +kubebuilder:default=true
	Compression bool `json:"compression,omitempty"`

	// Suspend pauses scheduled backups when true.
	// +optional
	Suspend bool `json:"suspend,omitempty"`
}

// BackupDestination defines the backup storage target.
type BackupDestination struct {
	// Type is the destination type.
	// +kubebuilder:validation:Enum=s3;gcs;pvc
	Type string `json:"type"`

	// Bucket is the S3/GCS bucket name.
	// +optional
	Bucket string `json:"bucket,omitempty"`

	// Path is the prefix/path within the bucket or PVC.
	// +optional
	Path string `json:"path,omitempty"`

	// SecretRef references credentials for the backup destination.
	// +optional
	SecretRef string `json:"secretRef,omitempty"`

	// PVCName is the PersistentVolumeClaim name (for pvc type).
	// +optional
	PVCName string `json:"pvcName,omitempty"`
}

// XDCBackupStatus defines the observed state of XDCBackup.
type XDCBackupStatus struct {
	// LastBackupTime is the timestamp of the last successful backup.
	// +optional
	LastBackupTime *metav1.Time `json:"lastBackupTime,omitempty"`

	// LastBackupSize is the size of the last backup in bytes.
	LastBackupSize int64 `json:"lastBackupSize,omitempty"`

	// BackupCount is the total number of stored backups.
	BackupCount int32 `json:"backupCount,omitempty"`

	// Phase is the current backup status.
	// +kubebuilder:validation:Enum=Active;Running;Failed;Suspended
	Phase string `json:"phase,omitempty"`

	// Conditions represent the latest available observations.
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Node",type=string,JSONPath=`.spec.nodeRef`
// +kubebuilder:printcolumn:name="Schedule",type=string,JSONPath=`.spec.schedule`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`

// XDCBackup is the Schema for the xdcbackups API.
type XDCBackup struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   XDCBackupSpec   `json:"spec,omitempty"`
	Status XDCBackupStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// XDCBackupList contains a list of XDCBackup.
type XDCBackupList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []XDCBackup `json:"items"`
}
