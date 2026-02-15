/*
Copyright 2024 XDC Network.
Licensed under the Apache License, Version 2.0.
*/

package controllers

import (
	"context"
	"fmt"
	"time"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// XDCBackupReconciler reconciles XDCBackup objects.
type XDCBackupReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=xdc.network,resources=xdcbackups,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=xdc.network,resources=xdcbackups/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=batch,resources=cronjobs;jobs,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=persistentvolumeclaims,verbs=get;list;watch

// Reconcile handles XDCBackup create/update/delete events.
func (r *XDCBackupReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	logger.Info("Reconciling XDCBackup", "name", req.NamespacedName)

	// TODO: Implement backup reconciliation logic:
	// 1. Fetch the XDCBackup resource
	// 2. Create/update a CronJob for the backup schedule
	// 3. Manage backup retention (delete old backups)
	// 4. Update status with last backup time and count
	// 5. Handle suspend/resume

	_ = errors.IsNotFound(nil)
	_ = fmt.Sprintf("")
	_ = time.Now()

	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *XDCBackupReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		// TODO: For(&xdcv1alpha1.XDCBackup{}).
		Complete(r)
}
