package PKG_PLACEHOLDER

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager

// تبديل أيقونة التطبيق: كل أيقونة activity-alias، ودائماً وحدة منها بس مفعّلة.
// نفعّل الجديدة أول، بعدين نطفي الباقي، حتى ما نصير بدون أيقونة أبداً.
object IconSwitcher {
    private val names = listOf("Default", "Rose", "Mint", "Sunset", "Night")

    private fun cn(ctx: Context, n: String): ComponentName =
        ComponentName(ctx.packageName, "com.bainatna.chat.Icon" + n)

    private fun exists(ctx: Context, n: String): Boolean {
        return try {
            ctx.packageManager.getActivityInfo(cn(ctx, n), PackageManager.MATCH_DISABLED_COMPONENTS)
            true
        } catch (e: Throwable) {
            false
        }
    }

    private fun isOn(ctx: Context, n: String): Boolean {
        val s = ctx.packageManager.getComponentEnabledSetting(cn(ctx, n))
        return s == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
            (s == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && n == "Default")
    }

    fun state(ctx: Context): Map<String, Any> {
        return try {
            val avail = names.filter { exists(ctx, it) }
            val cur = avail.firstOrNull { isOn(ctx, it) } ?: ""
            mapOf("available" to avail, "current" to cur)
        } catch (e: Throwable) {
            mapOf("available" to ArrayList<String>(), "current" to "")
        }
    }

    fun set(ctx: Context, name: String): Boolean {
        if (!names.contains(name) || !exists(ctx, name)) return false
        return try {
            val pm = ctx.packageManager
            pm.setComponentEnabledSetting(cn(ctx, name), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
            for (n in names) {
                if (n != name && exists(ctx, n)) {
                    pm.setComponentEnabledSetting(cn(ctx, n), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                }
            }
            true
        } catch (e: Throwable) {
            false
        }
    }
}
