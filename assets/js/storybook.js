// Register Bond's colocated JS hooks (e.g. the Menu positioner, SidePanel/Modal
// Escape handlers) with the Storybook LiveSocket so interactive components
// behave in the catalog exactly as they do in the app.
import {hooks as colocatedHooks} from "phoenix-colocated/local_cents"

;(function () {
  window.storybook = {Hooks: colocatedHooks}
})()


// If your components require alpinejs, you'll need to start
// alpine after the DOM is loaded and pass in an onBeforeElUpdated
// 
// import Alpine from 'alpinejs'
// window.Alpine = Alpine
// document.addEventListener('DOMContentLoaded', () => {
//   window.Alpine.start();
// });

// (function () {
//   window.storybook = {
//     LiveSocketOptions: {
//       dom: {
//         onBeforeElUpdated(from, to) {
//           if (from._x_dataStack) {
//             window.Alpine.clone(from, to)
//           }
//         }
//       }
//     }
//   };
// })();
