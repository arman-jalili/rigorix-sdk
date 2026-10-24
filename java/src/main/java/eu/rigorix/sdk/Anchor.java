package eu.rigorix.sdk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;
import org.bouncycastle.util.encoders.Hex;

import java.nio.charset.StandardCharsets;
import java.util.List;

/** ADR-016 anchor-signed artifacts — Ed25519 verification. */
public final class Anchor {

    private static final List<String> LEDGER_RECEIPT =
            List.of("ledger_id", "envelope_hash", "sequence", "recorded_at", "sig");
    private static final List<String> HISTORY_SLICE =
            List.of("scope", "since", "actions", "head_hash", "sig");
    private static final List<String> COMPACTION_CHECKPOINT =
            List.of("sequence_from", "sequence_to", "reason", "prior_head", "new_head", "sig");

    private Anchor() {
    }

    public static void verifyLedgerReceipt(JsonNode receipt, String publicKeyHex) {
        verify(receipt, LEDGER_RECEIPT, publicKeyHex);
    }

    public static void verifyHistorySlice(JsonNode slice, String publicKeyHex) {
        verify(slice, HISTORY_SLICE, publicKeyHex);
    }

    public static void verifyCompactionCheckpoint(JsonNode checkpoint, String publicKeyHex) {
        verify(checkpoint, COMPACTION_CHECKPOINT, publicKeyHex);
    }

    static void verify(JsonNode artifact, List<String> order, String publicKeyHex) {
        JsonNode sig = artifact.get("sig");
        if (sig == null || sig.isNull() || sig.asText().isEmpty()) {
            throw new VerifyException(VerifyException.Kind.ANCHOR_SIGNATURE, "artifact has no `sig`");
        }
        byte[] publicKey;
        byte[] signature;
        try {
            publicKey = Hex.decode(publicKeyHex);
            signature = Hex.decode(sig.asText());
        } catch (RuntimeException e) {
            throw new VerifyException(VerifyException.Kind.ANCHOR_SIGNATURE, "invalid hex: " + e.getMessage());
        }
        byte[] message = Canonical.withOrder((ObjectNode) artifact, order).getBytes(StandardCharsets.UTF_8);
        Ed25519Signer signer = new Ed25519Signer();
        try {
            signer.init(false, new Ed25519PublicKeyParameters(publicKey, 0));
        } catch (RuntimeException e) {
            throw new VerifyException(VerifyException.Kind.ANCHOR_SIGNATURE, "invalid public key: " + e.getMessage());
        }
        signer.update(message, 0, message.length);
        if (!signer.verifySignature(signature)) {
            throw new VerifyException(VerifyException.Kind.ANCHOR_SIGNATURE, "invalid Ed25519 anchor signature");
        }
    }
}
