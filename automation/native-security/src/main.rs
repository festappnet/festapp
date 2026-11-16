use glib::ToVariant;
fn main() {
    let values = vec!["alpha", "beta", "gamma", "delta"];
    let variant = values.to_variant();
    assert_eq!(
        variant.array_iter_str().unwrap().collect::<Vec<_>>(),
        values
    );
    assert_eq!(
        variant.array_iter_str().unwrap().rev().collect::<Vec<_>>(),
        vec!["delta", "gamma", "beta", "alpha"]
    );
    assert_eq!(variant.array_iter_str().unwrap().nth(2), Some("gamma"));
    assert_eq!(variant.array_iter_str().unwrap().nth_back(2), Some("beta"));
    assert_eq!(variant.array_iter_str().unwrap().last(), Some("delta"));
    println!("PASS optimized GLib VariantStrIter forward/backward/nth/nth_back/last");
}
