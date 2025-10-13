import sys
import subprocess
import time
import torch
import torch.nn as nn
import torch.nn.functional as F
import torch.optim as optim
from torch.utils.data import DataLoader

try:
    from torchvision import datasets, transforms
except:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'torchvision'])
    from torchvision import datasets, transforms


# Define the neural network model
class Net(nn.Module):
    def __init__(self):
        super(Net, self).__init__()
        self.fc1 = nn.Linear(28 * 28, 128)
        self.fc2 = nn.Linear(128, 10)

    def forward(self, x):
        x = x.view(-1, 28 * 28)  # Flatten the input
        x = F.relu(self.fc1(x))
        x = self.fc2(x)
        return x


def train(model, train_loader, optimizer, criterion, device, epoch):
    """Training function"""
    model.train()
    epoch_start_time = time.time()
    for batch_idx, (data, target) in enumerate(train_loader):
        data, target = data.to(device), target.to(device)
        
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        
        if batch_idx % 100 == 0:
            print(f'Train Epoch: {epoch} [{batch_idx * len(data)}/{len(train_loader.dataset)} '
                  f'({100. * batch_idx / len(train_loader):.0f}%)]\tLoss: {loss.item():.6f}')
    
    # Synchronize GPU to get accurate timing
    if torch.cuda.is_available():
        torch.cuda.synchronize()
    epoch_time = time.time() - epoch_start_time
    print(f'Training Epoch {epoch} completed in {epoch_time:.4f} seconds')


def test(model, test_loader, criterion, device):
    """Testing function"""
    model.eval()
    test_start_time = time.time()
    test_loss = 0
    correct = 0
    with torch.no_grad():
        for data, target in test_loader:
            data, target = data.to(device), target.to(device)
            output = model(data)
            test_loss += criterion(output, target).item()
            pred = output.argmax(dim=1, keepdim=True)
            correct += pred.eq(target.view_as(pred)).sum().item()
    
    # Synchronize GPU to get accurate timing
    if torch.cuda.is_available():
        torch.cuda.synchronize()
    test_time = time.time() - test_start_time
    test_loss /= len(test_loader)
    accuracy = 100. * correct / len(test_loader.dataset)
    print(f'\nTest set: Average loss: {test_loss:.4f}, '
          f'Accuracy: {correct}/{len(test_loader.dataset)} ({accuracy:.2f}%)')
    print(f'Testing completed in {test_time:.4f} seconds\n')


def main():
    """Main training and evaluation loop"""
    # Check if GPU is available
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Using device: {device}")
    if torch.cuda.is_available():
        print(f"GPU Name: {torch.cuda.get_device_name(0)}")
        print(f"GPU Count: {torch.cuda.device_count()}")
        print(f"CUDA Version: {torch.version.cuda}")
    else:
        print("WARNING: CUDA not available, running on CPU")

    # Data preprocessing
    transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.5,), (0.5,))  # Normalize to [-1, 1]
    ])

    # Load MNIST dataset
    train_dataset = datasets.MNIST(root='./data', train=True, download=True, transform=transform)
    test_dataset = datasets.MNIST(root='./data', train=False, download=True, transform=transform)

    # Create data loaders with num_workers > 0 for better performance on Linux/macOS
    # This is safe when wrapped in if __name__ == "__main__"
    train_loader = DataLoader(train_dataset, batch_size=128, shuffle=True, num_workers=2)
    test_loader = DataLoader(test_dataset, batch_size=128, shuffle=False, num_workers=2)

    # Initialize model, loss function, and optimizer
    model = Net().to(device)
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)

    # Train and evaluate
    print("=" * 60)
    print("Starting MNIST PyTorch Training")
    print("=" * 60)

    # Warm-up run to initialize CUDA kernels (for more accurate first epoch timing)
    if torch.cuda.is_available():
        print("Performing GPU warm-up...")
        dummy_input = torch.randn(1, 28, 28).to(device)
        _ = model(dummy_input)
        torch.cuda.synchronize()
        print("Warm-up complete.\n")

    total_start_time = time.time()

    for epoch in range(1, 7):  # 6 epochs
        train(model, train_loader, optimizer, criterion, device, epoch)
        test(model, test_loader, criterion, device)

    # Synchronize before final timing
    if torch.cuda.is_available():
        torch.cuda.synchronize()
    total_time = time.time() - total_start_time
    print("=" * 60)
    print(f"Training completed! Total time: {total_time:.4f} seconds ({total_time/60:.4f} minutes)")
    if torch.cuda.is_available():
        print(f"GPU utilized: {torch.cuda.get_device_name(0)}")
        print(f"Peak GPU memory allocated: {torch.cuda.max_memory_allocated(0) / 1024**2:.2f} MB")
    print("=" * 60)


if __name__ == "__main__":
    main()
