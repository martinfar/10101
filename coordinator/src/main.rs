use anyhow::Context;
use anyhow::Result;
use bitcoin::Network;
use coordinator::cli::Opts;
use coordinator::logger;
use coordinator::routes;
use ln_dlc_node::node::Node;
use ln_dlc_node::seed::Bip39Seed;
use rand::thread_rng;
use rand::RngCore;
use std::sync::Arc;
use tracing::metadata::LevelFilter;

const ELECTRS_ORIGIN: &str = "tcp://localhost:50000";

#[rocket::main]
async fn main() -> Result<()> {
    let opts = Opts::read();
    let data_dir = opts.data_dir()?;
    let address = opts.p2p_address;
    let http_address = opts.http_address;
    let network = Network::Regtest;

    logger::init_tracing(LevelFilter::DEBUG, false)?;

    let mut ephemeral_randomness = [0; 32];
    thread_rng().fill_bytes(&mut ephemeral_randomness);

    let data_dir = data_dir.join(network.to_string());
    if !data_dir.exists() {
        std::fs::create_dir_all(&data_dir)
            .context(format!("Could not create data dir for {network}"))?;
    }

    let seed_path = data_dir.join("seed");
    let seed = Bip39Seed::initialize(&seed_path)?;

    let node = Arc::new(
        Node::new_coordinator(
            "coordinator".to_string(),
            network,
            data_dir.as_path(),
            address,
            ELECTRS_ORIGIN.to_string(),
            seed,
            ephemeral_randomness,
        )
        .await,
    );

    tokio::spawn({
        let node = node.clone();
        async move {
            loop {
                // todo: the node sync should not swallow the error.
                node.sync();
                tokio::time::sleep(std::time::Duration::from_secs(10)).await;
            }
        }
    });

    tokio::spawn({
        let node = node.clone();
        async move {
            let background_processor = node.start().await.expect("background processor to start");
            if let Err(err) = background_processor.join() {
                tracing::error!(?err, "Background processor stopped unexpected");
            }
        }
    });

    let figment = rocket::Config::figment()
        .merge(("address", http_address.ip()))
        .merge(("port", http_address.port()));

    let mission_success = rocket::custom(figment)
        .mount(
            "/api",
            rocket::routes![
                routes::get_fake_scid,
                routes::get_new_address,
                routes::get_balance
            ],
        )
        .manage(node)
        .launch()
        .await?;

    tracing::trace!(?mission_success, "Rocket has landed");

    Ok(())
}
