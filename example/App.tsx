import { getSubjectAsync } from "expo-ios-bg-remover";
import { useEffect, useState } from "react";
import { Image, StyleSheet, View } from "react-native";

export default function App() {
  const [bgRemovedUri, setBgRemovedUri] = useState<string | null>(null);

  const removeBg = async () => {
    // load uri from local image
    const localImage = require("./assets/car.jpg");
    const asset = Image.resolveAssetSource(localImage);

    const result = await getSubjectAsync(asset.uri);

    setBgRemovedUri(result.uri);
  };

  useEffect(() => {
    removeBg();
  }, []);

  return (
    <View style={styles.container}>
      <Image
        source={require("./assets/car.jpg")}
        style={{ width: 200, height: 200 }}
        resizeMode="contain"
      />
      {bgRemovedUri && (
        <Image
          source={{ uri: bgRemovedUri }}
          style={{ width: 200, height: 200 }}
          resizeMode="contain"
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#fff",
    alignItems: "center",
    justifyContent: "center",
  },
});
