package com.adamhunt.retroguide.purchases

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.android.billingclient.api.acknowledgePurchase
import com.android.billingclient.api.queryProductDetails
import com.android.billingclient.api.queryPurchasesAsync
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * RetroGuide Pro on Google Play (the Apple app's `ProStore`): a one-time
 * purchase, checked at launch and whenever Play reports a change, that
 * unlocks the extras. Bought on one Android device, it applies on every
 * device signed in to the same Google account.
 */
class ProStore(context: Context, private val scope: CoroutineScope) {
    /** The product, with the same id as on the App Store. */
    private object Product {
        const val PRO = "com.adamhunt.retroguide.pro"
    }

    sealed interface PurchaseState {
        data object Idle : PurchaseState
        data object Purchasing : PurchaseState
        /** Waiting on the payment (cash, a parent's approval): Pro unlocks when it goes through. */
        data object Pending : PurchaseState
        data class Failed(val message: String) : PurchaseState
    }

    private val _isPro = MutableStateFlow(false)
    val isPro: StateFlow<Boolean> = _isPro.asStateFlow()
    /** Ownership has been checked since launch. */
    private val _hasLoaded = MutableStateFlow(false)
    val hasLoaded: StateFlow<Boolean> = _hasLoaded.asStateFlow()
    /** The price as Google Play shows it ("$4.99"), once loaded. */
    private val _price = MutableStateFlow<String?>(null)
    val price: StateFlow<String?> = _price.asStateFlow()
    private val _isLoadingProduct = MutableStateFlow(false)
    val isLoadingProduct: StateFlow<Boolean> = _isLoadingProduct.asStateFlow()
    private val _state = MutableStateFlow<PurchaseState>(PurchaseState.Idle)
    val state: StateFlow<PurchaseState> = _state.asStateFlow()

    private var product: ProductDetails? = null
    private val client = BillingClient.newBuilder(context)
        .setListener { result, purchases -> scope.launch { handle(result, purchases) } }
        .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
        .enableAutoServiceReconnection()
        .build()

    /** Connects to Google Play, then checks ownership and loads the product. */
    fun start() {
        scope.launch {
            if (!connect()) {
                _hasLoaded.value = true
                return@launch
            }
            refreshOwnership()
            _hasLoaded.value = true
            loadProduct()
        }
    }

    fun purchase(activity: Activity) {
        val details = product ?: return
        _state.value = PurchaseState.Purchasing
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details).build()))
            .build()
        val result = client.launchBillingFlow(activity, params)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) _state.value = failure(result)
    }

    /** Checks Google Play again (after a reinstall, or a purchase on another device). */
    fun restore() {
        scope.launch {
            if (connect()) refreshOwnership()
        }
    }

    /** Loads the product if an earlier try failed (no network at launch). */
    fun loadProductIfNeeded() {
        if (product != null || _isLoadingProduct.value) return
        scope.launch { if (connect()) loadProduct() }
    }

    private suspend fun connect(): Boolean {
        if (client.isReady) return true
        return suspendCancellableCoroutine { continuation ->
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(result: BillingResult) {
                    if (continuation.isActive) continuation.resume(result.responseCode == BillingClient.BillingResponseCode.OK)
                }

                override fun onBillingServiceDisconnected() {
                    if (continuation.isActive) continuation.resume(false)
                }
            })
        }
    }

    private suspend fun loadProduct() {
        _isLoadingProduct.value = true
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(Product.PRO).setProductType(BillingClient.ProductType.INAPP).build(),
        )).build()
        val result = client.queryProductDetails(params)
        product = result.productDetailsList?.firstOrNull()
        _price.value = product?.oneTimePurchaseOfferDetailsList?.firstOrNull()?.formattedPrice
        _isLoadingProduct.value = false
    }

    private suspend fun refreshOwnership() {
        val result = client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build())
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) return
        val owned = result.purchasesList.filter(::grantsPro)
        owned.forEach { acknowledge(it) }
        _isPro.value = owned.isNotEmpty()
    }

    private suspend fun handle(result: BillingResult, purchases: List<Purchase>?) {
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val bought = purchases.orEmpty().filter { Product.PRO in it.products }
                bought.firstOrNull { it.purchaseState == Purchase.PurchaseState.PENDING }?.let { _state.value = PurchaseState.Pending }
                bought.filter(::grantsPro).forEach { purchase ->
                    acknowledge(purchase)
                    _isPro.value = true
                    _state.value = PurchaseState.Idle
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> _state.value = PurchaseState.Idle
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                refreshOwnership()
                _state.value = PurchaseState.Idle
            }
            else -> _state.value = failure(result)
        }
    }

    /** Google Play refunds purchases not acknowledged within three days. */
    private suspend fun acknowledge(purchase: Purchase) {
        if (purchase.isAcknowledged) return
        client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build())
    }

    private fun grantsPro(purchase: Purchase) =
        Product.PRO in purchase.products && purchase.purchaseState == Purchase.PurchaseState.PURCHASED

    private fun failure(result: BillingResult) =
        PurchaseState.Failed(result.debugMessage.ifBlank { "Google Play couldn't complete the purchase." })
}
