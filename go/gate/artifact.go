// The artifact's identity: the digest and size recorded in PROVENANCE.md and
// in the Python binding, checked before the bytes are compiled.
//
// The import table is cheap to reproduce in a hostile module; the digest is not.
// A gate that only validates the shape would accept an artifact that decides
// differently, so `Open` refuses bytes that are not the recorded artifact.
package gate

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
)

// artifactSHA256 is the recorded digest of the embedded artifact. PROVENANCE.md,
// the Python binding and scripts/check-vendored-artifact.sh record the same
// value; that guard fails if any of them drifts.
const artifactSHA256 = "7414f8df8772c789b38aeae7460f2f50c816bdde2848bc99470e0b273010bc9c"

// artifactSize is the recorded byte length (1,896,910).
const artifactSize = 1_896_910

// ErrArtifactDigestMismatch means the bytes are not the recorded artifact.
// errors.Is matches it against *ArtifactDigestError.
var ErrArtifactDigestMismatch = errors.New("artifact digest mismatch")

// ArtifactDigestError names both digests, so a support case can say which
// artifact was loaded and which one was expected.
type ArtifactDigestError struct {
	Expected     string
	Actual       string
	ExpectedSize int
	ActualSize   int
}

func (e *ArtifactDigestError) Error() string {
	return fmt.Sprintf(
		"artifact digest mismatch: expected %s (%d bytes), got %s (%d bytes)",
		e.Expected, e.ExpectedSize, e.Actual, e.ActualSize,
	)
}

// Is lets errors.Is(err, ErrArtifactDigestMismatch) hold for a typed refusal.
func (e *ArtifactDigestError) Is(target error) bool {
	return target == ErrArtifactDigestMismatch
}

// verifyArtifact checks size and digest before compilation. Size is compared
// first because it costs nothing and still names both values.
func verifyArtifact(wasm []byte) error {
	actual := hex.EncodeToString(sum256(wasm))
	if len(wasm) == artifactSize && actual == artifactSHA256 {
		return nil
	}
	return &ArtifactDigestError{
		Expected:     artifactSHA256,
		Actual:       actual,
		ExpectedSize: artifactSize,
		ActualSize:   len(wasm),
	}
}

func sum256(wasm []byte) []byte {
	sum := sha256.Sum256(wasm)
	return sum[:]
}
