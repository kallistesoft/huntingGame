extends Node
## In-app purchases. PLACEHOLDER: every purchase succeeds at once and nothing
## is charged.
##
## Later: Google Play Billing on Android, StoreKit on iOS. Replace purchase()
## with the plugin calls and call on_done.call(true) only once the store
## confirms the payment. Product ids are the keys of Data.PACKS.


func purchase(product_id: String, on_done: Callable) -> void:
	if not Data.PACKS.has(product_id):
		on_done.call(false)
		return
	on_done.call(true)
