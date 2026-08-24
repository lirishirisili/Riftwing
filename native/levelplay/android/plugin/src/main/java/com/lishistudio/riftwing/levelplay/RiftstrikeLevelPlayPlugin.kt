package com.lishistudio.riftwing.levelplay

import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

import com.unity3d.mediation.LevelPlay
import com.unity3d.mediation.LevelPlayAdError
import com.unity3d.mediation.LevelPlayAdInfo
import com.unity3d.mediation.LevelPlayAdSize
import com.unity3d.mediation.LevelPlayConfiguration
import com.unity3d.mediation.LevelPlayInitError
import com.unity3d.mediation.LevelPlayInitListener
import com.unity3d.mediation.LevelPlayInitRequest
import com.unity3d.mediation.banner.LevelPlayBannerAdView
import com.unity3d.mediation.banner.LevelPlayBannerAdViewListener
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAd
import com.unity3d.mediation.interstitial.LevelPlayInterstitialAdListener
import com.unity3d.mediation.rewarded.LevelPlayReward
import com.unity3d.mediation.rewarded.LevelPlayRewardedAd
import com.unity3d.mediation.rewarded.LevelPlayRewardedAdListener

/**
 * RIFTSTRIKE LevelPlay bridge (Godot Android v2 plugin).
 *
 * Wraps the current Unity LevelPlay ad-unit APIs (mediation-sdk 9.6.0):
 * LevelPlay.init + LevelPlayInterstitialAd / LevelPlayRewardedAd /
 * LevelPlayBannerAdView. No legacy IronSource init/load/show APIs are used.
 *
 * Init happens once; ad objects are created only after init success. All
 * LevelPlay UI calls run on the UI thread; results are re-emitted to Godot as
 * signals consumed by `LevelPlayAdsService`.
 */
class RiftstrikeLevelPlayPlugin(godot: Godot) : GodotPlugin(godot) {

    companion object {
        private const val PLUGIN_NAME = "RiftstrikeLevelPlay"
        private const val TAG = "RiftstrikeLevelPlay"
    }

    @Volatile private var initialized = false
    @Volatile private var initInProgress = false

    private var interstitialAdUnitId: String = ""
    private var rewardedAdUnitId: String = ""
    private var bannerAdUnitId: String = ""

    private var interstitialAd: LevelPlayInterstitialAd? = null
    private var rewardedAd: LevelPlayRewardedAd? = null

    private var bannerAdView: LevelPlayBannerAdView? = null
    private var bannerContainer: FrameLayout? = null

    @Volatile private var interstitialReady = false
    @Volatile private var rewardedReady = false

    override fun getPluginName(): String = PLUGIN_NAME

    override fun getPluginSignals(): MutableSet<SignalInfo> {
        return mutableSetOf(
            SignalInfo("init_success"),
            SignalInfo("init_failed", String::class.java),
            SignalInfo("banner_loaded"),
            SignalInfo("banner_load_failed", String::class.java),
            SignalInfo("banner_clicked"),
            SignalInfo("interstitial_loaded"),
            SignalInfo("interstitial_load_failed", String::class.java),
            SignalInfo("interstitial_displayed"),
            SignalInfo("interstitial_display_failed", String::class.java),
            SignalInfo("interstitial_closed"),
            SignalInfo("interstitial_clicked"),
            SignalInfo("rewarded_loaded"),
            SignalInfo("rewarded_load_failed", String::class.java),
            SignalInfo("rewarded_displayed"),
            SignalInfo("rewarded_display_failed", String::class.java),
            SignalInfo("rewarded_closed"),
            SignalInfo("rewarded_clicked"),
            SignalInfo("rewarded_earned", String::class.java, Integer::class.java)
        )
    }

    // --- Initialization -----------------------------------------------------

    @UsedByGodot
    fun initialize(
        appKey: String,
        bannerId: String,
        interstitialId: String,
        rewardedId: String,
        development: Boolean
    ) {
        if (initialized || initInProgress) {
            return
        }
        val activity = activity
        if (activity == null) {
            emitSignal("init_failed", "no activity available")
            return
        }
        bannerAdUnitId = bannerId
        interstitialAdUnitId = interstitialId
        rewardedAdUnitId = rewardedId
        initInProgress = true

        activity.runOnUiThread {
            try {
                if (development) {
                    // Verbose LevelPlay logs while integrating; harmless in release if left on.
                    LevelPlay.setMetaData("is_test_suite", "enable")
                }
                val initRequest = LevelPlayInitRequest.Builder(appKey).build()
                LevelPlay.init(activity, initRequest, object : LevelPlayInitListener {
                    override fun onInitSuccess(configuration: LevelPlayConfiguration) {
                        initInProgress = false
                        initialized = true
                        createAdObjects()
                        emitSignal("init_success")
                    }

                    override fun onInitFailed(error: LevelPlayInitError) {
                        initInProgress = false
                        initialized = false
                        emitSignal("init_failed", describe(error))
                    }
                })
            } catch (t: Throwable) {
                initInProgress = false
                emitSignal("init_failed", t.message ?: t.toString())
            }
        }
    }

    private fun createAdObjects() {
        interstitialAd = LevelPlayInterstitialAd(interstitialAdUnitId).apply {
            setListener(interstitialListener)
        }
        rewardedAd = LevelPlayRewardedAd(rewardedAdUnitId).apply {
            setListener(rewardedListener)
        }
    }

    // --- Banner -------------------------------------------------------------

    @UsedByGodot
    fun show_banner() {
        val activity = activity ?: return
        if (!initialized) return
        activity.runOnUiThread {
            try {
                if (bannerAdView == null) {
                    val adSize = LevelPlayAdSize.createAdaptiveAdSize(activity)
                        ?: LevelPlayAdSize.BANNER
                    val adConfig = LevelPlayBannerAdView.Config.Builder()
                        .setAdSize(adSize)
                        .build()
                    val view = LevelPlayBannerAdView(activity, bannerAdUnitId, adConfig)
                    view.setBannerListener(bannerListener)

                    val container = FrameLayout(activity)
                    val params = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                    val viewParams = FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    ).apply { gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL }
                    container.addView(view, viewParams)
                    activity.addContentView(container, params)

                    bannerAdView = view
                    bannerContainer = container
                }
                bannerContainer?.visibility = View.VISIBLE
                bannerAdView?.loadAd()
            } catch (t: Throwable) {
                emitSignal("banner_load_failed", t.message ?: t.toString())
            }
        }
    }

    @UsedByGodot
    fun hide_banner() {
        val activity = activity ?: return
        activity.runOnUiThread {
            bannerContainer?.visibility = View.GONE
        }
    }

    @UsedByGodot
    fun destroy_banner() {
        val activity = activity ?: return
        activity.runOnUiThread {
            try {
                bannerAdView?.destroy()
                bannerContainer?.let { (it.parent as? ViewGroup)?.removeView(it) }
            } catch (_: Throwable) {
            } finally {
                bannerAdView = null
                bannerContainer = null
            }
        }
    }

    // --- Interstitial -------------------------------------------------------

    @UsedByGodot
    fun load_interstitial() {
        val activity = activity ?: return
        if (!initialized) return
        activity.runOnUiThread {
            interstitialReady = false
            interstitialAd?.loadAd()
        }
    }

    @UsedByGodot
    fun is_interstitial_ready(): Boolean = interstitialReady

    @UsedByGodot
    fun show_interstitial() {
        val activity = activity ?: return
        activity.runOnUiThread {
            interstitialAd?.showAd(activity)
        }
    }

    // --- Rewarded -----------------------------------------------------------

    @UsedByGodot
    fun load_rewarded() {
        val activity = activity ?: return
        if (!initialized) return
        activity.runOnUiThread {
            rewardedReady = false
            rewardedAd?.loadAd()
        }
    }

    @UsedByGodot
    fun is_rewarded_ready(): Boolean = rewardedReady

    @UsedByGodot
    fun show_rewarded() {
        val activity = activity ?: return
        activity.runOnUiThread {
            rewardedAd?.showAd(activity)
        }
    }

    // --- Lifecycle / dev ----------------------------------------------------

    @UsedByGodot
    fun on_pause() {
        // New LevelPlay APIs manage the activity lifecycle automatically; kept
        // for the GDScript contract. Do NOT call legacy IronSource.onPause here.
    }

    @UsedByGodot
    fun on_resume() {
        // See on_pause().
    }

    @UsedByGodot
    fun launch_test_suite() {
        val activity = activity ?: return
        activity.runOnUiThread {
            try {
                LevelPlay.launchTestSuite(activity)
            } catch (_: Throwable) {
            }
        }
    }

    // --- Listeners ----------------------------------------------------------

    private val interstitialListener = object : LevelPlayInterstitialAdListener {
        override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
            interstitialReady = true
            emitSignal("interstitial_loaded")
        }

        override fun onAdLoadFailed(error: LevelPlayAdError) {
            interstitialReady = false
            emitSignal("interstitial_load_failed", describe(error))
        }

        override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {
            interstitialReady = false
            emitSignal("interstitial_displayed")
        }

        override fun onAdDisplayFailed(error: LevelPlayAdError, adInfo: LevelPlayAdInfo) {
            interstitialReady = false
            emitSignal("interstitial_display_failed", describe(error))
        }

        override fun onAdClicked(adInfo: LevelPlayAdInfo) {
            emitSignal("interstitial_clicked")
        }

        override fun onAdClosed(adInfo: LevelPlayAdInfo) {
            emitSignal("interstitial_closed")
        }

        override fun onAdInfoChanged(adInfo: LevelPlayAdInfo) {}
    }

    private val rewardedListener = object : LevelPlayRewardedAdListener {
        override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
            rewardedReady = true
            emitSignal("rewarded_loaded")
        }

        override fun onAdLoadFailed(error: LevelPlayAdError) {
            rewardedReady = false
            emitSignal("rewarded_load_failed", describe(error))
        }

        override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {
            rewardedReady = false
            emitSignal("rewarded_displayed")
        }

        override fun onAdDisplayFailed(error: LevelPlayAdError, adInfo: LevelPlayAdInfo) {
            rewardedReady = false
            emitSignal("rewarded_display_failed", describe(error))
        }

        override fun onAdClicked(adInfo: LevelPlayAdInfo) {
            emitSignal("rewarded_clicked")
        }

        override fun onAdClosed(adInfo: LevelPlayAdInfo) {
            emitSignal("rewarded_closed")
        }

        override fun onAdInfoChanged(adInfo: LevelPlayAdInfo) {}

        override fun onAdRewarded(reward: LevelPlayReward, adInfo: LevelPlayAdInfo) {
            emitSignal("rewarded_earned", reward.name ?: "", Integer.valueOf(reward.amount))
        }
    }

    private val bannerListener = object : LevelPlayBannerAdViewListener {
        override fun onAdLoaded(adInfo: LevelPlayAdInfo) {
            emitSignal("banner_loaded")
        }

        override fun onAdLoadFailed(error: LevelPlayAdError) {
            emitSignal("banner_load_failed", describe(error))
        }

        override fun onAdDisplayed(adInfo: LevelPlayAdInfo) {}

        override fun onAdDisplayFailed(adInfo: LevelPlayAdInfo, error: LevelPlayAdError) {
            emitSignal("banner_load_failed", describe(error))
        }

        override fun onAdClicked(adInfo: LevelPlayAdInfo) {
            emitSignal("banner_clicked")
        }

        override fun onAdExpanded(adInfo: LevelPlayAdInfo) {}

        override fun onAdCollapsed(adInfo: LevelPlayAdInfo) {}

        override fun onAdLeftApplication(adInfo: LevelPlayAdInfo) {}
    }

    private fun describe(error: LevelPlayAdError): String {
        return "code=${error.errorCode} message=${error.errorMessage}"
    }

    private fun describe(error: LevelPlayInitError): String {
        return "code=${error.errorCode} message=${error.errorMessage}"
    }
}
