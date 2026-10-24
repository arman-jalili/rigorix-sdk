package eu.rigorix.sdk.client;

/** A JSON-RPC 2.0 error object surfaced as an exception. */
public class RpcException extends RuntimeException {

    private final int code;

    public RpcException(int code, String message) {
        super("jsonrpc error " + code + ": " + message);
        this.code = code;
    }

    public int code() {
        return code;
    }
}
