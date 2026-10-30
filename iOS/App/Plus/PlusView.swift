// Màn "VietTelex Plus": quyền lợi, mua, khôi phục, trạng thái, ủng hộ (tip).
import SwiftUI

/// Model dùng chung toàn app (một backend StoreKit, một listener Transaction.updates).
@MainActor
enum PlusShared {
    static let model = PlusStoreModel(backend: StoreKitPlusBackend())
}

/// Dòng mở màn Plus — đặt trong List của tab Giới Thiệu.
struct PlusEntryRow: View {
    @ObservedObject var model: PlusStoreModel = PlusShared.model
    var body: some View {
        NavigationLink {
            PlusView(model: model)
        } label: {
            HStack {
                Label("VietTelex Plus", systemImage: "star.circle")
                Spacer()
                if model.isPlus {
                    Text(L("Đã mở khoá")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct PlusView: View {
    @ObservedObject var model: PlusStoreModel
    @AppStorage(PlusConfig.debugOverrideKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var debugOverride = false
    @AppStorage(PlusOnboarding.addTonesKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var addTonesChip = false
    @AppStorage(PlusFeature.textToolsKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var textToolsEnabled = true
    @AppStorage(PlusFeature.aiProofreadKey, store: UserDefaults(suiteName: PlusConfig.appGroup))
    private var aiProofread = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: model.isPlus ? "star.circle.fill" : "star.circle")
                        .font(.system(size: 56))
                        .foregroundStyle(accentBlue)
                    Text("VietTelex Plus").font(.title2.bold())
                    Text(model.isPlus
                         ? L("Cảm ơn bạn đã ủng hộ VietTelex ★")
                         : L("Mua một lần, dùng mãi mãi. Không thuê bao, không quảng cáo."))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            if !PlusGate.paywallEnabled {
                Section {
                    Text(L("Trong giai đoạn này mọi tính năng Plus đang mở miễn phí cho tất cả mọi người."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(PlusFeature.allCases.filter(\.isAvailableOnDevice)) { f in
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(f.title)
                            Text(f.detail).font(.footnote).foregroundStyle(.secondary)
                            Text(f.howTo).font(.footnote).foregroundStyle(accentBlue)
                            if f.settingKey != nil, PlusGate.isUnlocked(f) {
                                Toggle(isOn: f == .textTools ? $textToolsEnabled : f == .aiProofread ? $aiProofread : $addTonesChip) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.settingTitle)
                                        if let sub = f.settingSubtitle {
                                            Text(sub).font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .font(.subheadline).tint(.green)
                                .disabled(f == .aiProofread && !AISettingUI.current.isEnabled)
                                if f == .aiProofread, let hint = AISettingUI.current.hint {
                                    Text(hint).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            if f == .translate, PlusGate.isUnlocked(f), #available(iOS 26.0, *) {
                                NavigationLink(L("Ngôn ngữ & gói dịch")) { TranslateSettingsView() }
                                    .font(.subheadline)
                            }
                        }
                    } icon: {
                        Image(systemName: f.systemImage).foregroundStyle(accentBlue)
                    }
                }
            } header: { Text(L("Quyền lợi Plus")) } footer: {
                Text(L("Toàn bộ phần gõ — Telex/VNI, sửa dấu từ đã gõ, gợi ý, gõ vuốt, gõ tắt, mẫu câu, theme sáng/tối — luôn miễn phí."))
            }

            Section {
                if model.isPlus {
                    Label(L("Bạn đã có VietTelex Plus"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task { await model.buy(PlusConfig.plusProductID) }
                    } label: {
                        HStack {
                            Text(L("Mở khoá Plus")).bold()
                            Spacer()
                            if model.busyProductID == PlusConfig.plusProductID {
                                ProgressView()
                            } else {
                                Text(model.plusProduct?.displayPrice ?? PlusConfig.plusPriceHint)
                            }
                        }
                    }
                    .disabled(model.plusProduct == nil || model.busyProductID != nil)
                }
                Button {
                    Task { await model.restore() }
                } label: {
                    HStack {
                        Text(L("Khôi phục giao dịch"))
                        Spacer()
                        if model.isRestoring { ProgressView() }
                    }
                }
                .disabled(model.isRestoring)
            } header: { Text(L("Mua")) } footer: {
                Text(L("Thanh toán qua Apple ID. Đã mua trên máy khác cùng Apple ID thì bấm Khôi phục."))
            }

            Section {
                ForEach(model.tipProducts) { tip in
                    Button {
                        Task { await model.buy(tip.id) }
                    } label: {
                        HStack {
                            Text(tip.displayName)
                            Spacer()
                            if model.busyProductID == tip.id { ProgressView() } else { Text(tip.displayPrice) }
                        }
                    }
                    .disabled(model.busyProductID != nil)
                }
                if model.tipProducts.isEmpty {
                    Text(L("Chưa tải được các mức ủng hộ.")).font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text(L("Ủng hộ tác giả")) } footer: {
                Text(L("Tuỳ tâm, không mở khoá thêm gì — giúp VietTelex tiếp tục miễn phí và mã nguồn mở."))
            }

            if let msg = model.message {
                Section { Text(msg).font(.footnote) }
            }

            #if DEBUG
            Section {
                Toggle(L("Giả lập đã mua Plus"), isOn: $debugOverride).tint(.green)
            } header: { Text("Debug") } footer: {
                Text(L("Chỉ có trong bản Debug. Bàn phím đọc cùng cờ qua App Group."))
            }
            #endif
        }
        .navigationTitle("VietTelex Plus")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadProducts()
            await model.refreshEntitlements()
        }
        .onChange(of: debugOverride) { _ in model.objectWillChange.send() }
        .alert(L("Bật chip “Thêm dấu”?"), isPresented: $model.offerAddTones) {
            Button(L("Bật ngay")) { model.acceptAddTonesOffer() }
            Button(L("Để sau"), role: .cancel) {}
        } message: {
            Text(L("Gõ không dấu cả câu, gõ dấu cách rồi chạm chip “Thêm dấu” ở đầu thanh gợi ý. Chip đang tắt — bật ngay? (Đổi lại ở Tính Năng → Gợi ý & từ điển.)"))
        }
    }
}
