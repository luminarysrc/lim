.pragma library

// Time left until a Unix timestamp: "3d 4h", "2h 13m" or "45m".
function timeUntil(epochSeconds) {
    const minutes = Math.max(0, Math.round((epochSeconds * 1000 - Date.now()) / 60000))
    const days = Math.floor(minutes / 1440)
    const hours = Math.floor(minutes % 1440 / 60)

    if (days > 0) return `${days}d ${hours}h`
    if (hours > 0) return `${hours}h ${minutes % 60}m`
    return `${minutes}m`
}

// Text colour that warns as a limit gets close.
function usageColor(used, theme) {
    if (used >= 90) return theme.negativeTextColor
    if (used >= 70) return theme.neutralTextColor
    return theme.textColor
}
