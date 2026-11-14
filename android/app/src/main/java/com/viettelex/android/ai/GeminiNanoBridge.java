package com.viettelex.android.ai;

import androidx.annotation.Nullable;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.genai.common.FeatureStatus;
import com.google.mlkit.genai.prompt.Candidate;
import com.google.mlkit.genai.prompt.GenerateContentRequest;
import com.google.mlkit.genai.prompt.GenerateContentResponse;
import com.google.mlkit.genai.prompt.Generation;
import com.google.mlkit.genai.prompt.TextPart;
import com.google.mlkit.genai.prompt.java.GenerativeModelFutures;
import java.util.List;
import java.util.concurrent.Executor;

/**
 * Cầu nối Java tới ML Kit GenAI Prompt API (Gemini Nano). Viết bằng JAVA vì SDK biên dịch bằng
 * Kotlin metadata 2.2 mà project đang Kotlin 2.0 (đọc tối đa 2.1) — Java không kiểm metadata. API
 * lộ ra chỉ dùng kiểu Java. Nâng Kotlin ≥ 2.2 thì có thể gộp về GeminiNanoAddress.kt.
 */
public final class GeminiNanoBridge {
    public interface Callback { void done(@Nullable String text); }
    public interface StatusCallback { void done(boolean available); }

    private static GenerativeModelFutures model;
    /** Máy không hỗ trợ (UNAVAILABLE) — nhớ tới hết process, khỏi hỏi lại. */
    private static volatile boolean unsupported;

    private GeminiNanoBridge() {}

    private static synchronized GenerativeModelFutures client() {
        if (model == null) model = GenerativeModelFutures.from(Generation.INSTANCE.getClient());
        return model;
    }

    /** Model dùng được NGAY (AVAILABLE) — cho màn cài đặt quyết định hiện công tắc. */
    public static void status(Executor executor, StatusCallback cb) {
        if (unsupported) { cb.done(false); return; }
        try {
            ListenableFuture<Integer> status = client().checkStatus();
            status.addListener(() -> {
                int s;
                try { s = status.get(); } catch (Exception e) { cb.done(false); return; }
                if (s == FeatureStatus.UNAVAILABLE) unsupported = true;
                cb.done(s == FeatureStatus.AVAILABLE);
            }, executor);
        } catch (Throwable t) {
            cb.done(false);
        }
    }

    /** Kiểm trạng thái rồi sinh (temperature 0). Không tự tải model (DOWNLOADABLE ⇒ null). */
    public static void run(String prompt, int maxOutputTokens, Executor executor, Callback cb) {
        if (unsupported) { cb.done(null); return; }
        try {
            GenerativeModelFutures m = client();
            ListenableFuture<Integer> status = m.checkStatus();
            status.addListener(() -> {
                int s;
                try { s = status.get(); } catch (Exception e) { cb.done(null); return; }
                if (s == FeatureStatus.UNAVAILABLE) unsupported = true;
                if (s != FeatureStatus.AVAILABLE) { cb.done(null); return; }
                GenerateContentRequest.Builder b = new GenerateContentRequest.Builder(new TextPart(prompt));
                b.setTemperature(0f);
                b.setMaxOutputTokens(maxOutputTokens);
                ListenableFuture<GenerateContentResponse> f = m.generateContent(b.build());
                f.addListener(() -> {
                    String text = null;
                    try {
                        List<Candidate> c = f.get().getCandidates();
                        if (!c.isEmpty()) text = c.get(0).getText();
                    } catch (Exception ignored) { }
                    cb.done(text);
                }, executor);
            }, executor);
        } catch (Throwable t) {
            cb.done(null);
        }
    }
}
