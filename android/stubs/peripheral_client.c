/*
 * Stub libperipheral_client.so for Android vendor daemons on Ubuntu.
 *
 * The real library talks to pm-service over (vnd)binder to vote a
 * peripheral (the modem) online. We have no binder service manager; the
 * modem is held up by modem.service instead. So every call succeeds and
 * the peripheral is reported as already online.
 *
 * API as in CAF's peripheral manager (libperipheralclient):
 *   enum pm_event { GOING_OFFLINE, IS_OFFLINE, GOING_ONLINE, IS_ONLINE };
 *   PM_RET_SUCCESS = 0
 * Built freestanding (no libc) for the bionic linker; see
 * scripts/build-android-stubs.sh.
 */
enum pm_event {
    EVENT_PERIPH_GOING_OFFLINE,
    EVENT_PERIPH_IS_OFFLINE,
    EVENT_PERIPH_GOING_ONLINE,
    EVENT_PERIPH_IS_ONLINE,
};

typedef void (*pm_client_notifier)(void *client_data, enum pm_event event);

static int dummy_handle;

int pm_client_register(pm_client_notifier cb, void *client_data,
                       const char *dev_name, const char *client_name,
                       enum pm_event *state, void **handle)
{
    (void)cb; (void)client_data; (void)dev_name; (void)client_name;
    if (state)
        *state = EVENT_PERIPH_IS_ONLINE;
    if (handle)
        *handle = &dummy_handle;
    return 0;
}

int pm_client_connect(void *handle) { (void)handle; return 0; }
int pm_client_disconnect(void *handle) { (void)handle; return 0; }
int pm_client_unregister(void *handle) { (void)handle; return 0; }
int pm_client_event_acknowledge(void *handle, enum pm_event event)
{
    (void)handle; (void)event;
    return 0;
}
