import Foundation

/// Значения по умолчанию. Их можно заполнить до сборки —
/// или ввести позже прямо в приложении (экраны «Настройка» и «Настройки»).
enum AppConfig {
    /// База REST API Z.AI. Для материкового Китая: https://open.bigmodel.cn/api/paas/v4
    static let defaultZaiBaseURL = "https://api.z.ai/api/paas/v4"

    /// Модель по умолчанию (меняется в настройках приложения).
    static let defaultModel = "glm-4.6"

    /// Данные вашего проекта Supabase (supabase.com → Settings → API).
    /// Пример URL: https://abcdefgh.supabase.co
    static let defaultSupabaseURL = "https://aqmssswzigdcqphoyyne.supabase.co"
    static let defaultSupabaseAnonKey = "sb_publishable_Fy3vbny0lM2Oz7uM2Rx_6A__xjokhV1"
}
