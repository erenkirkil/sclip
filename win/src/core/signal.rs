use std::cell::RefCell;
use std::rc::Rc;

type Listener<T> = Box<dyn FnMut(&T)>;

struct SignalInner<T> {
    next_id: u64,
    listeners: Vec<(u64, Listener<T>)>,
}

/// Single-threaded reactive signal for ViewModel state notifications.
pub struct Signal<T> {
    inner: Rc<RefCell<SignalInner<T>>>,
}

impl<T> Clone for Signal<T> {
    fn clone(&self) -> Self {
        Self {
            inner: Rc::clone(&self.inner),
        }
    }
}

impl<T: 'static> Default for Signal<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T: 'static> Signal<T> {
    pub fn new() -> Self {
        Self {
            inner: Rc::new(RefCell::new(SignalInner {
                next_id: 1,
                listeners: Vec::new(),
            })),
        }
    }

    pub fn subscribe<F>(&self, listener: F) -> Subscription
    where
        F: FnMut(&T) + 'static,
    {
        let mut inner = self.inner.borrow_mut();
        let id = inner.next_id;
        inner.next_id += 1;
        inner.listeners.push((id, Box::new(listener)));
        let weak = Rc::downgrade(&self.inner);
        Subscription {
            unsubscribe: Some(Box::new(move || {
                if let Some(rc) = weak.upgrade() {
                    if let Ok(mut guard) = rc.try_borrow_mut() {
                        guard.listeners.retain(|(item_id, _)| *item_id != id);
                    }
                }
            })),
        }
    }

    pub fn send(&self, value: &T) {
        let mut inner = self.inner.borrow_mut();
        for (_, listener) in inner.listeners.iter_mut() {
            listener(value);
        }
    }
}

/// RAII subscription token that unsubscribes when dropped or cancelled.
pub struct Subscription {
    unsubscribe: Option<Box<dyn FnOnce()>>,
}

impl Subscription {
    pub fn cancel(&mut self) {
        if let Some(unsub) = self.unsubscribe.take() {
            unsub();
        }
    }
}

impl Drop for Subscription {
    fn drop(&mut self) {
        self.cancel();
    }
}
