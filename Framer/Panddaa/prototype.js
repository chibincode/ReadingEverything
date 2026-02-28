const modal = document.getElementById("detail-modal");
const openButtons = document.querySelectorAll("[data-open-detail]");
const closeButton = document.querySelector("[data-close-detail]");

if (modal && openButtons.length > 0 && closeButton) {
  const openModal = () => {
    modal.classList.add("open");
    modal.setAttribute("aria-hidden", "false");
  };

  const closeModal = () => {
    modal.classList.remove("open");
    modal.setAttribute("aria-hidden", "true");
  };

  openButtons.forEach((button) => {
    button.addEventListener("click", openModal);
  });

  closeButton.addEventListener("click", closeModal);

  modal.addEventListener("click", (event) => {
    if (event.target === modal) closeModal();
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") closeModal();
  });
}
