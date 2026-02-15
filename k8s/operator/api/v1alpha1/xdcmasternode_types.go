/*
Copyright 2024 XDC Network.
Licensed under the Apache License, Version 2.0.
*/

package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// XDCMasternodeSpec defines the desired state of an XDC masternode.
type XDCMasternodeSpec struct {
	// Network is the XDC network (mainnet or testnet).
	// +kubebuilder:validation:Enum=mainnet;testnet
	Network string `json:"network"`

	// Coinbase is the masternode's coinbase address.
	Coinbase string `json:"coinbase"`

	// StakingAmount is the amount of XDC staked (default "10000000").
	// +optional
	StakingAmount string `json:"stakingAmount,omitempty"`

	// KeystoreSecret references a Kubernetes secret containing the keystore.
	KeystoreSecret string `json:"keystoreSecret"`

	// NodeRef references the XDCNode resource this masternode is associated with.
	// +optional
	NodeRef string `json:"nodeRef,omitempty"`

	// Image is the container image for the masternode.
	// +optional
	Image string `json:"image,omitempty"`

	// Resources defines CPU/memory requests and limits.
	// +optional
	Resources *ResourceRequirements `json:"resources,omitempty"`
}

// ResourceRequirements defines compute resources.
type ResourceRequirements struct {
	CPURequest    string `json:"cpuRequest,omitempty"`
	CPULimit      string `json:"cpuLimit,omitempty"`
	MemoryRequest string `json:"memoryRequest,omitempty"`
	MemoryLimit   string `json:"memoryLimit,omitempty"`
}

// XDCMasternodeStatus defines the observed state of XDCMasternode.
type XDCMasternodeStatus struct {
	// Phase is the current lifecycle phase.
	// +kubebuilder:validation:Enum=Pending;Registering;Active;Resigned;Failed
	Phase string `json:"phase,omitempty"`

	// Epoch is the current epoch number.
	Epoch int64 `json:"epoch,omitempty"`

	// Conditions represent the latest available observations.
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Network",type=string,JSONPath=`.spec.network`
// +kubebuilder:printcolumn:name="Coinbase",type=string,JSONPath=`.spec.coinbase`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`

// XDCMasternode is the Schema for the xdcmasternodes API.
type XDCMasternode struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   XDCMasternodeSpec   `json:"spec,omitempty"`
	Status XDCMasternodeStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// XDCMasternodeList contains a list of XDCMasternode.
type XDCMasternodeList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []XDCMasternode `json:"items"`
}
