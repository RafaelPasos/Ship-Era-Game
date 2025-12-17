# Naval Adventure

Welcome to Naval Adventure, a 2.5D top-down naval action game for iOS! Take command of your own ship, navigate treacherous waters, and battle waves of enemy vessels. Collect loot, upgrade your ship, and become the most feared captain on the high seas.



## Features

*   **Dynamic Combat:** Engage in real-time naval battles with a variety of enemy ships.
*   **Joystick Navigation:** Smooth and intuitive joystick control for ship movement.
*   **Auto-Targeting:** Lock onto enemies and unleash continuous fire.
*   **Loot & Economy:** Defeat enemies to collect gold and valuable repair kits.
*   **Deep Upgrade System:** Use your loot to upgrade your ship's performance in multiple categories:
    *   **Gunnery:** Increase damage and critical hit chance.
    *   **Ordnance:** Improve reload speed and cannonball types.
    *   **Carpenter:** Add more cannons to your volleys.
    *   **Shipyard:** Boost your ship's movement speed.
*   **Varied Enemy AI:** Face off against standard ships, aggressive chasers, and formidable Dreadnought bosses.
*   **Procedurally Generated World:** Every wave features a unique layout of islands and challenges.
*   **Visual Feedback:** See the action unfold with damage indicators, smoke effects on damaged ships, and explosion animations.

## Architecture

This project is built using a modern hybrid architecture that combines the power of Apple's native frameworks:

*   **SpriteKit:** The core game engine, responsible for rendering, physics, and all real-time game logic.
*   **SwiftUI:** Used to build the entire user interface, including the HUD, menus, and the upgrade store.

This separation allows for a clean and maintainable codebase, leveraging the strengths of each framework.

## How to Run the Project

1.  Make sure you have Xcode installed.
2.  Clone this repository to your local machine.
3.  Open the `ShipTapper.xcodeproj` file in Xcode.
4.  Select your target device (or a simulator).
5.  Click the "Run" button (or press `Cmd+R`).

## Future Development

This project is an ongoing work in progress. Here are some of the planned improvements:

*   **Sound Design:** Adding background music and sound effects for a more immersive experience.
*   **Visual Polish:** Replacing placeholder graphics with high-quality sprites and adding more particle effects.
*   **Advanced AI:** Creating more complex and challenging enemy behaviors.
*   **Persistence:** Implementing a save system to store player progress.
