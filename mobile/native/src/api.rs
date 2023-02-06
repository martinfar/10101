use crate::api_model;
use crate::api_model::event::flutter_subscriber::FlutterSubscriber;
use crate::api_model::order::NewOrder;
use crate::api_model::order::Order;
use crate::api_model::Direction;
use crate::calculations;
use crate::event;
use crate::ln_dlc;
use crate::logger;
use crate::trade::order;
use anyhow::Result;
use flutter_rust_bridge::StreamSink;
use flutter_rust_bridge::SyncReturn;

/// Initialise logging infrastructure for Rust
pub fn init_logging(sink: StreamSink<logger::LogEntry>) {
    logger::create_log_stream(sink)
}

pub struct WalletInfo {
    pub balances: Balances,
    pub history: Vec<Transaction>,
}

pub struct Balances {
    pub on_chain: u64,
    pub lightning: u64,
}

#[tokio::main(flavor = "current_thread")]
pub async fn refresh_wallet_info() -> WalletInfo {
    WalletInfo {
        balances: Balances {
            on_chain: 300,
            lightning: 104,
        },
        history: vec![
            Transaction {
                address: "loremipsum".to_string(),
                flow: Flow::Inbound,
                amount_sats: 300,
                wallet_type: WalletType::OnChain,
            },
            Transaction {
                address: "dolorsitamet".to_string(),
                flow: Flow::Inbound,
                amount_sats: 104,
                wallet_type: WalletType::Lightning,
            },
        ],
    }
}

pub struct Transaction {
    // TODO(Restioson): newtype?
    pub address: String,
    pub flow: Flow,
    // TODO(Restioson): newtype?
    pub amount_sats: u64,
    pub wallet_type: WalletType,
}

pub enum WalletType {
    OnChain,
    Lightning,
}

#[allow(dead_code)] // used in dart
pub enum Flow {
    Inbound,
    Outbound,
}

pub fn calculate_margin(price: f64, quantity: f64, leverage: f64) -> SyncReturn<u64> {
    SyncReturn(calculations::calculate_margin(price, quantity, leverage))
}

pub fn calculate_quantity(price: f64, margin: u64, leverage: f64) -> SyncReturn<f64> {
    SyncReturn(calculations::calculate_quantity(price, margin, leverage))
}

pub fn calculate_liquidation_price(
    price: f64,
    leverage: f64,
    direction: Direction,
) -> SyncReturn<f64> {
    SyncReturn(calculations::calculate_liquidation_price(
        price, leverage, direction,
    ))
}

#[tokio::main(flavor = "current_thread")]
pub async fn submit_order(order: NewOrder) -> Result<()> {
    order::handler::submit_order(order.into()).await?;
    Ok(())
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_order(id: String) -> Result<Order> {
    let order = order::handler::get_order(id).await?.into();
    Ok(order)
}

#[tokio::main(flavor = "current_thread")]
pub async fn get_orders() -> Result<Vec<Order>> {
    let orders = order::handler::get_orders()
        .await?
        .into_iter()
        .map(|order| order.into())
        .collect::<Vec<Order>>();

    Ok(orders)
}

pub fn subscribe(stream: StreamSink<api_model::event::Event>) {
    tracing::debug!("Subscribing flutter to event hub");
    event::subscribe(FlutterSubscriber::new(stream))
}

pub fn run(app_dir: String) -> Result<()> {
    ln_dlc::run(app_dir)
}

pub fn get_new_address() -> SyncReturn<String> {
    SyncReturn(ln_dlc::get_new_address().unwrap())
}

pub fn open_channel() -> Result<()> {
    ln_dlc::open_channel()
}

pub fn create_invoice() -> Result<String> {
    Ok(ln_dlc::create_invoice()?.to_string())
}

pub fn send_payment(invoice: String) -> Result<()> {
    ln_dlc::send_payment(&invoice)
}
