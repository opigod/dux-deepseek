import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "deepseek"

    StyledText {
        width: parent.width
        text: "DeepSeek"
        font.pixelSize: Theme.fontSizeXLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Peak/off-peak countdown, balance and platform usage in one bar widget. No Python, no browser automation."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText {
        width: parent.width
        text: "Bar"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "displayMode"
        label: "Bar display"
        description: "What the bar pill shows. Vertical bars use the compact countdown or balance."
        options: [
            { label: "Peak + balance", value: "peakBalance" },
            { label: "Peak only", value: "peak" },
            { label: "Balance first", value: "balance" },
            { label: "Icon only", value: "icon" }
        ]
        defaultValue: "peakBalance"
    }

    ToggleSetting {
        settingKey: "showProgress"
        label: "Show block progress"
        description: "A thin line under the countdown showing progress through the current peak or off-peak block."
        defaultValue: true
    }

    ColorSetting {
        settingKey: "offPeakColor"
        label: "Off-peak color"
        description: "Dot and countdown color outside peak hours."
        defaultValue: "#4ade80"
    }

    ColorSetting {
        settingKey: "peakColor"
        label: "Peak color"
        description: "Dot and countdown color during peak hours."
        defaultValue: "#f87171"
    }

    ColorSetting {
        settingKey: "driftColor"
        label: "Drift color"
        description: "Shown when the published pricing page no longer matches the bundled schedule."
        defaultValue: "#fbbf24"
    }

    StyledText {
        width: parent.width
        text: "Peak schedule"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    ToggleSetting {
        id: showOllamaSetting
        settingKey: "showOllama"
        label: "Show Ollama Cloud"
        description: "Show the Ollama Cloud schedule in the Providers card. Turning this off also switches the active schedule back to DeepSeek."
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "provider"
        label: "Peak schedule provider"
        description: "DeepSeek: 01:00-04:00 and 06:00-10:00 UTC, Mon-Fri. Ollama Cloud: 12:00-18:00 UTC, Mon-Fri."
        options: showOllamaSetting.value
            ? [
                { label: "DeepSeek", value: "deepseek" },
                { label: "Ollama Cloud", value: "ollama" }
            ]
            : [
                { label: "DeepSeek", value: "deepseek" }
            ]
        defaultValue: "deepseek"
    }

    ToggleSetting {
        settingKey: "autoCheck"
        label: "Check the pricing page"
        description: "Periodically fetch the public pricing page and warn if the published peak windows changed. No API key is used."
        defaultValue: true
    }

    SliderSetting {
        settingKey: "checkIntervalH"
        label: "Pricing check interval"
        description: "Hours between pricing-page checks."
        defaultValue: 6
        minimum: 1
        maximum: 24
        unit: " h"
    }

    ToggleSetting {
        settingKey: "offlineOnly"
        label: "Offline only"
        description: "Keep the peak countdown but disable every network request."
        defaultValue: false
    }

    StringSetting {
        settingKey: "customSourceUrl"
        label: "Custom pricing page URL"
        description: "Optional mirror used for drift checks. Leave empty for the official page."
        placeholder: "https://..."
        defaultValue: ""
    }

    StyledText {
        width: parent.width
        text: "Account"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "API key"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Used for the official balance endpoint. Leave empty to use the DEEPSEEK_API_KEY environment variable. Stored in plain text in the gitignored plugin settings."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: apiKeyField
                width: Math.max(80, parent.width - saveKeyButton.width - clearKeyButton.width - parent.spacing * 2)
                placeholderText: "sk-..."
                echoMode: TextInput.Password
                showPasswordToggle: true
                onEditingFinished: root.saveApiKey()
            }

            DButton {
                id: saveKeyButton
                text: "Save"
                variant: "tonal"
                onClicked: root.saveApiKey()
            }

            DButton {
                id: clearKeyButton
                text: "Clear"
                variant: "text"
                onClicked: {
                    apiKeyField.text = "";
                    root.saveValue("apiKey", "");
                    ToastService.showInfo("DeepSeek", "API key cleared");
                }
            }
        }

        Row {
            spacing: Theme.spacingS

            DButton {
                text: "Open API keys"
                iconName: "open_in_new"
                variant: "text"
                onClicked: Qt.openUrlExternally("https://platform.deepseek.com/api_keys")
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Platform session token"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Optional. Unlocks monthly tokens, cost, token estimate and the daily chart. On platform.deepseek.com open Usage, press F12, open Network, click get_user_summary and copy the authorization request header (or the full Cookie). Masked and stored only in the gitignored plugin settings."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: platformField
                width: Math.max(80, parent.width - savePlatformButton.width - clearPlatformButton.width - parent.spacing * 2)
                placeholderText: "Bearer ... or session cookie"
                echoMode: TextInput.Password
                showPasswordToggle: true
                onEditingFinished: root.savePlatformToken()
            }

            DButton {
                id: savePlatformButton
                text: "Save"
                variant: "tonal"
                onClicked: root.savePlatformToken()
            }

            DButton {
                id: clearPlatformButton
                text: "Clear"
                variant: "text"
                onClicked: {
                    platformField.text = "";
                    root.saveValue("platformAuth", "");
                    ToastService.showInfo("DeepSeek", "Platform token cleared");
                }
            }
        }

        Row {
            spacing: Theme.spacingS

            DButton {
                text: "Open platform"
                iconName: "open_in_new"
                variant: "text"
                onClicked: Qt.openUrlExternally("https://platform.deepseek.com/usage")
            }
        }

        StyledText {
            width: parent.width
            text: "The token expires when the platform logs you out. When that happens the widget asks for a new one instead of retrying with the old token."
            font.pixelSize: Theme.fontSizeXSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    StyledText {
        width: parent.width
        text: "Usage"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Theme.fontWeightMedium
        color: Theme.surfaceText
    }

    SliderSetting {
        settingKey: "refreshMinutes"
        label: "Refresh interval"
        description: "Minutes between balance and usage refreshes. The daemon is shared by every bar instance."
        defaultValue: 5
        minimum: 1
        maximum: 60
        unit: " min"
    }

    SelectionSetting {
        settingKey: "historyMonths"
        label: "History"
        description: "Months of token and cost history to keep. Older months are fetched once a day."
        options: [
            { label: "Current month", value: "1" },
            { label: "Last 3 months", value: "3" },
            { label: "Last 6 months", value: "6" }
        ]
        defaultValue: "3"
    }

    StyledText {
        width: parent.width
        text: "IPC: dms ipc call deepseek status | refresh | checkPricing"
        font.pixelSize: Theme.fontSizeXSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    Component.onCompleted: {
        Qt.callLater(function () {
            apiKeyField.text = root.loadValue("apiKey", "");
            platformField.text = root.loadValue("platformAuth", "");
        });
    }

    function saveApiKey() {
        root.saveValue("apiKey", String(apiKeyField.text || "").trim());
        ToastService.showInfo("DeepSeek", "API key saved");
    }

    function savePlatformToken() {
        root.saveValue("platformAuth", String(platformField.text || "").trim());
        ToastService.showInfo("DeepSeek", "Platform token saved");
    }
}
