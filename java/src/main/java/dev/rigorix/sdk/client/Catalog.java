package dev.rigorix.sdk.client;

import java.util.List;
import java.util.Optional;

/**
 * The frozen {@code rigorix.*} catalog as a client-side binding table (ADR-0001
 * D3). Every method is either {@link Kind#TYPED} or explicitly
 * {@link Kind#SERVER_ONLY}; there is deliberately no raw step-execution method
 * (ADR-0001 D10). The drift test fails if this diverges from
 * {@code schemas/api/catalog.json}.
 */
public final class Catalog {

    /** How (or whether) the client binds a method. */
    public enum Kind {
        TYPED,
        SERVER_ONLY
    }

    /** A frozen method and its client binding. */
    public record Method(String name, Kind kind, String reason) {
        public static Method typed(String name) {
            return new Method(name, Kind.TYPED, "");
        }

        public static Method serverOnly(String name, String reason) {
            return new Method(name, Kind.SERVER_ONLY, reason);
        }
    }

    /** The frozen catalog binding table. */
    public static final List<Method> METHODS = List.of(
            Method.typed("rigorix.plan"),
            Method.typed("rigorix.validatePlan"),
            Method.typed("rigorix.run"),
            Method.typed("rigorix.execute"),
            Method.typed("rigorix.approve"),
            Method.typed("rigorix.checkEnforcement"),
            Method.typed("rigorix.audit.read"),
            Method.typed("rigorix.audit.list"),
            Method.typed("rigorix.audit.summary"),
            Method.serverOnly("rigorix.audit.head", "enterprise ADR-016 Phase B ledger surface"),
            Method.serverOnly("rigorix.audit.history", "enterprise ADR-016 Phase B ledger surface"),
            Method.serverOnly("rigorix.audit.overdue", "enterprise ADR-016 Phase B ledger surface"),
            Method.typed("rigorix.template.list"),
            Method.typed("rigorix.template.get"),
            Method.typed("rigorix.template.create"),
            Method.typed("rigorix.template.validate"),
            Method.typed("rigorix.auth.login"),
            Method.typed("rigorix.auth.status"),
            Method.typed("rigorix.auth.logout"),
            Method.serverOnly("rigorix.auth.verify", "enterprise-side JWKS claim verification"),
            Method.serverOnly("rigorix.policy.bundle", "admin/enterprise control-plane export"),
            Method.typed("rigorix.usageGuide"),
            Method.typed("rigorix.system.version"));

    private Catalog() {
    }

    /** Every bound catalog method name. */
    public static List<String> names() {
        return METHODS.stream().map(Method::name).toList();
    }

    /** The binding for a method name, if any. */
    public static Optional<Method> find(String name) {
        return METHODS.stream().filter(method -> method.name().equals(name)).findFirst();
    }

    /** Fail if a raw step-execution binding appears (ADR-0001 D10). */
    public static void assertNoRawStepExecution() {
        for (Method method : METHODS) {
            if (method.name().equals("rigorix.executeStep")) {
                throw new IllegalStateException("raw step execution must never be bound: " + method.name());
            }
        }
    }
}
