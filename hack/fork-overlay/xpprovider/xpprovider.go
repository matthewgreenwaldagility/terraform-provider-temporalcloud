// Package xpprovider re-exports the Temporal Cloud Terraform Plugin Framework
// provider so Upjet's no-fork (TFPF) runtime can construct it in-process.
//
// This file is the *only* thing this fork adds on top of upstream
// terraform-provider-temporalcloud. It lives at the module root (not under
// internal/) so external modules can import it, while it is itself allowed to
// import the upstream internal/provider package because it is part of the same
// module.
//
// It is applied as an additive overlay on top of an unmodified upstream release
// tag by hack/sync-xp-fork.sh. It intentionally edits no upstream file, so it
// can never merge-conflict with an upstream release. The only thing that can
// break it is upstream changing provider.New's signature or moving the package,
// which `go build ./...` in the sync script detects loudly.
package xpprovider

import (
	fwprovider "github.com/hashicorp/terraform-plugin-framework/provider"

	"github.com/temporalio/terraform-provider-temporalcloud/internal/provider"
)

// GetProvider returns the Temporal Cloud Terraform Plugin Framework provider
// INSTANCE for Upjet's no-fork runtime. provider.New returns a factory
// (func() provider.Provider), so we invoke it once here to hand back the
// instance the runtime expects.
func GetProvider(version string) fwprovider.Provider {
	return provider.New(version)()
}
